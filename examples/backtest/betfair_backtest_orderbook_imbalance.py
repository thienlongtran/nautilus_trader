#!/usr/bin/env python3
# -------------------------------------------------------------------------------------------------
#  Copyright (C) 2015-2022 Nautech Systems Pty Ltd. All rights reserved.
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

from nautilus_trader.adapters.betfair.common import BETFAIR_VENUE
from nautilus_trader.adapters.betfair.providers import BetfairInstrumentProvider
from nautilus_trader.adapters.betfair.util import make_betfair_reader
from nautilus_trader.backtest.data.providers import TestDataProvider
from nautilus_trader.backtest.engine import BacktestEngine
from nautilus_trader.backtest.engine import BacktestEngineConfig
from nautilus_trader.examples.strategies.orderbook_imbalance import OrderBookImbalance
from nautilus_trader.examples.strategies.orderbook_imbalance import OrderBookImbalanceConfig
from nautilus_trader.model.currencies import GBP
from nautilus_trader.model.enums import AccountType
from nautilus_trader.model.enums import BookType
from nautilus_trader.model.enums import OMSType
from nautilus_trader.model.instruments.betting import BettingInstrument
from nautilus_trader.model.objects import Money


if __name__ == "__main__":
    # Configure backtest engine
    config = BacktestEngineConfig(
        trader_id="BACKTESTER-001",
        exec_engine={"allow_cash_positions": True},  # Retain original behaviour for now
    )
    # Build the backtest engine
    engine = BacktestEngine(config=config)

    # Load data
    raw_data = TestDataProvider().read("1.166564490.bz2")
    instrument_provider = BetfairInstrumentProvider.from_instruments([])
    reader = make_betfair_reader(instrument_provider=instrument_provider)
    data = list(reader.parse(raw_data))
    instruments = [d for d in data if isinstance(d, BettingInstrument)]
    data = [d for d in data if not isinstance(d, BettingInstrument)]

    for instrument in instruments:
        engine.add_instrument(instrument)
    engine.add_data(data)

    # Add an exchange (multiple exchanges possible)
    # Add starting balances for single-currency or multi-currency accounts
    engine.add_venue(
        venue=BETFAIR_VENUE,
        oms_type=OMSType.NETTING,
        account_type=AccountType.CASH,  # Spot cash account
        base_currency=None,  # Multi-currency account
        starting_balances=[Money(1_000_000, GBP)],
        book_type=BookType.L2_MBP,
    )

    # Configure your strategy
    config = OrderBookImbalanceConfig(
        instrument_id=str(instrument.id),
        max_trade_size=100,
        order_id_tag="001",
        use_book_deltas=False,
        check_orderbook_integrity=True,
    )
    # Instantiate and add your strategy
    strategy = OrderBookImbalance(config=config)
    engine.add_strategy(strategy=strategy)

    # Run the engine (from start to end of data)
    engine.run()

    # For repeated backtest runs make sure to reset the engine
    engine.reset()

    # Good practice to dispose of the object
    engine.dispose()
