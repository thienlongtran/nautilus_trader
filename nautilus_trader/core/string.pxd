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

from libc.stdint cimport uint8_t

from nautilus_trader.core.rust.core cimport cstring_free


cdef inline const char* pystr_to_cstring(str value) except *:
    return value.encode("utf-8") + b"\x00"  # Add NUL byte (hex literal)


cdef inline str cstring_to_pystr(const char* ptr):
    cdef str value = ptr.decode()  # Copy decoded UTF-8 bytes from `ptr` to PyObject str
    cstring_free(ptr)  # `ptr` moved to Rust (then dropped)
    return value


cpdef uint8_t precision_from_str(str value) except *