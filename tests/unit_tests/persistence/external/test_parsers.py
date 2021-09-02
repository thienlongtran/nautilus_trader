# -------------------------------------------------------------------------------------------------
#  Copyright (C) 2015-2021 Nautech Systems Pty Ltd. All rights reserved.
#  https://nautechsystems.io
#
#  Licensed under the GNU Lesser General Public License Version 3.0 (the "License");
#  You may not use this file except in compliance with the License.
#  You may obtain a copy of the License at https://www.gnu.org/licenses/lgpl-3.0.en.html
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
# -------------------------------------------------------------------------------------------------
import pathlib
import sys
from functools import partial
from unittest.mock import Mock

import fsspec.implementations.memory
import orjson
import pandas as pd
import pytest

from nautilus_trader.adapters.betfair.providers import BetfairInstrumentProvider
from nautilus_trader.core.datetime import dt_to_unix_nanos
from nautilus_trader.data.wrangling import QuoteTickDataWrangler
from nautilus_trader.model.instruments.currency import CurrencySpot
from nautilus_trader.persistence.catalog import DataCatalog
from nautilus_trader.persistence.external.core import make_raw_files
from nautilus_trader.persistence.external.core import process_raw_file
from nautilus_trader.persistence.external.parsers import ByteReader
from nautilus_trader.persistence.external.parsers import CSVReader
from nautilus_trader.persistence.external.parsers import LinePreprocessor
from nautilus_trader.persistence.external.parsers import ParquetReader
from nautilus_trader.persistence.external.parsers import TextReader
from tests.integration_tests.adapters.betfair.test_kit import BetfairDataProvider
from tests.integration_tests.adapters.betfair.test_kit import BetfairTestStubs
from tests.test_kit import PACKAGE_ROOT
from tests.test_kit.mocks import MockReader
from tests.test_kit.mocks import data_catalog_setup
from tests.test_kit.providers import TestInstrumentProvider
from tests.test_kit.stubs import TestStubs


TEST_DATA_DIR = str(pathlib.Path(PACKAGE_ROOT).joinpath("data"))

pytestmark = pytest.mark.skipif(sys.platform == "win32", reason="test path broken on windows")


class TestPersistenceParsers:
    def setup(self):
        data_catalog_setup()
        self.catalog = DataCatalog.from_env()
        self.reader = MockReader()
        self.mock_catalog = self._mock_catalog()
        self.line_preprocessor = TestLineProcessor()

    @staticmethod
    def _mock_catalog():
        mock_catalog = Mock(spec=DataCatalog)
        mock_catalog.path = "/root"
        mock_catalog.fs = fsspec.implementations.memory.MemoryFileSystem()
        return mock_catalog

    def test_line_preprocessor_preprocess(self):
        line = b'2021-06-29T06:04:11.943000 - {"op":"mcm","id":1,"clk":"AOkiAKEMAL4P","pt":1624946651810}\n'
        line, data = self.line_preprocessor.pre_process(line=line)
        assert line == b'{"op":"mcm","id":1,"clk":"AOkiAKEMAL4P","pt":1624946651810}'
        assert data == {"ts_init": 1624946651943000000}

    def test_line_preprocessor_post_process(self):
        obj = TestStubs.trade_tick_5decimal()
        data = {
            "ts_init": dt_to_unix_nanos(
                pd.Timestamp("2021-06-29T06:04:11.943000", tz="UTC").to_pydatetime()
            )
        }
        obj = self.line_preprocessor.post_process(obj=obj, state=data)
        assert obj.ts_init == 1624946651943000000

    def test_byte_reader_parser(self):
        def block_parser(block: bytes, instrument_provider):
            for raw in block.split(b"\\n"):
                ts, line = raw.split(b" - ")
                state = {
                    "ts_init": dt_to_unix_nanos(pd.Timestamp(ts.decode(), tz="UTC").to_pydatetime())
                }
                line = line.strip().replace(b"b'", b"")
                orjson.loads(line)
                for obj in BetfairTestStubs.parse_betfair(
                    line, instrument_provider=instrument_provider
                ):
                    values = obj.to_dict(obj)
                    values["ts_init"] = state["ts_init"]
                    yield obj.from_dict(values)

        provider = BetfairInstrumentProvider.from_instruments(
            [BetfairTestStubs.betting_instrument()]
        )
        block = BetfairDataProvider.badly_formatted_log()
        reader = ByteReader(
            block_parser=partial(block_parser, instrument_provider=provider),
            instrument_provider=provider,
        )

        data = list(reader.parse(block=block))
        result = [pd.Timestamp(d.ts_init).isoformat() for d in data]
        expected = ["2021-06-29T06:03:14.528000"]
        assert result == expected

    def test_text_reader_instrument(self):
        def parser(line):
            from decimal import Decimal

            from nautilus_trader.model.currencies import BTC
            from nautilus_trader.model.currencies import USDT
            from nautilus_trader.model.enums import AssetClass
            from nautilus_trader.model.enums import AssetType
            from nautilus_trader.model.identifiers import InstrumentId
            from nautilus_trader.model.identifiers import Symbol
            from nautilus_trader.model.identifiers import Venue
            from nautilus_trader.model.objects import Price
            from nautilus_trader.model.objects import Quantity

            assert (  # type: ignore  # noqa: F631
                Decimal,
                AssetType,
                AssetClass,
                USDT,
                BTC,
                CurrencySpot,
                InstrumentId,
                Symbol,
                Venue,
                Price,
                Quantity,
            )  # Ensure imports stay

            # Replace str repr with "fully qualified" string we can `eval`
            replacements = {
                b"id=BTC/USDT.BINANCE": b"instrument_id=InstrumentId(Symbol('BTC/USDT'), venue=Venue('BINANCE'))",
                b"price_increment=0.01": b"price_increment=Price.from_str('0.01')",
                b"size_increment=0.000001": b"size_increment=Quantity.from_str('0.000001')",
                b"margin_init=0": b"margin_init=Decimal(0)",
                b"margin_maint=0": b"margin_maint=Decimal(0)",
                b"maker_fee=0.001": b"maker_fee=Decimal(0.001)",
                b"taker_fee=0.001": b"taker_fee=Decimal(0.001)",
            }
            for k, v in replacements.items():
                line = line.replace(k, v)

            yield eval(line)  # noqa: S307

        reader = TextReader(line_parser=parser)
        raw_file = make_raw_files(glob_path=f"{TEST_DATA_DIR}/binance-btcusdt-instrument.txt")[0]
        result = process_raw_file(catalog=self.mock_catalog, raw_file=raw_file, reader=reader)
        expected = 1
        assert result == expected

    def test_csv_reader_dataframe(self):
        def parser(data):
            if data is None:
                return
            data.loc[:, "timestamp"] = pd.to_datetime(data["timestamp"])
            wrangler = QuoteTickDataWrangler(
                instrument=TestInstrumentProvider.default_fx_ccy("AUD/USD"),
                data_quotes=data.set_index("timestamp"),
            )
            wrangler.pre_process(0)
            yield from wrangler.build_ticks()

        reader = CSVReader(block_parser=parser, as_dataframe=True)
        raw_file = make_raw_files(glob_path=f"{TEST_DATA_DIR}/truefx-audusd-ticks.csv")[0]
        result = process_raw_file(catalog=self.mock_catalog, raw_file=raw_file, reader=reader)
        assert result == 100000

    def test_text_reader(self):
        provider = BetfairInstrumentProvider.from_instruments([])
        reader = BetfairTestStubs.betfair_reader(provider)  # type: TextReader
        raw_file = make_raw_files(glob_path=f"{TEST_DATA_DIR}/betfair/1.166811431.bz2")[0]
        result = process_raw_file(catalog=self.mock_catalog, raw_file=raw_file, reader=reader)
        assert result == 22692

    def test_byte_json_parser(self):
        def parser(block):
            for data in orjson.loads(block):
                obj = CurrencySpot.from_dict(data)
                yield obj

        reader = ByteReader(block_parser=parser)
        raw_file = make_raw_files(glob_path=f"{TEST_DATA_DIR}/crypto*.json")[0]
        result = process_raw_file(catalog=self.mock_catalog, raw_file=raw_file, reader=reader)
        assert result == 6

    def test_parquet_reader(self):
        def parser(data):
            if data is None:
                return
            data.loc[:, "timestamp"] = pd.to_datetime(data["timestamp"])
            data = data.set_index("timestamp")[["bid", "ask", "bid_size", "ask_size"]]
            wrangler = QuoteTickDataWrangler(
                instrument=TestInstrumentProvider.default_fx_ccy("AUD/USD"),
                data_quotes=data,
            )
            wrangler.pre_process(0)
            yield from wrangler.build_ticks()

        reader = ParquetReader(parser=parser)
        raw_file = make_raw_files(glob_path=f"{TEST_DATA_DIR}/binance-btcusdt-quotes.parquet")[0]
        result = process_raw_file(catalog=self.mock_catalog, raw_file=raw_file, reader=reader)
        assert result == 451


class TestLineProcessor(LinePreprocessor):
    @staticmethod
    def pre_process(line):
        ts, raw = line.split(b" - ")
        data = {"ts_init": dt_to_unix_nanos(pd.Timestamp(ts.decode(), tz="UTC").to_pydatetime())}
        line = raw.strip()
        return line, data

    @staticmethod
    def post_process(obj, state):
        values = obj.to_dict(obj)
        values["ts_init"] = state["ts_init"]
        return obj.from_dict(values)