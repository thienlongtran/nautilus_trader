# Warning, this file is autogenerated by cbindgen. Don't modify this manually. */

from cpython.object cimport PyObject
from libc.stdint cimport uint8_t, uint64_t, int64_t
from nautilus_trader.core.rust.core cimport UUID4_t

cdef extern from "../includes/common.h":

    cdef enum LogColor:
        NORMAL # = 0,
        GREEN # = 1,
        BLUE # = 2,
        MAGENTA # = 3,
        CYAN # = 4,
        YELLOW # = 5,
        RED # = 6,

    cdef enum LogLevel:
        DEBUG # = 10,
        INFO # = 20,
        WARNING # = 30,
        ERROR # = 40,
        CRITICAL # = 50,

    cdef struct Logger_t:
        pass

    cdef struct Option_PyObject:
        pass

    cdef struct TestClock:
        pass

    cdef struct CTestClock:
        TestClock *_0;

    # Logger is not C FFI safe, so we box and pass it as an opaque pointer.
    # This works because Logger fields don't need to be accessed, only functions
    # are called.
    cdef struct CLogger:
        Logger_t *_0;

    CTestClock test_clock_new();

    void test_clock_register_default_handler(CTestClock *clock, PyObject handler);

    # # Safety
    # - `name` must be borrowed from a valid Python UTF-8 `str`.
    void test_clock_set_time_alert_ns(CTestClock *clock,
                                      PyObject name,
                                      uint64_t alert_time_ns,
                                      Option_PyObject callback);

    # # Safety
    # - `name` must be borrowed from a valid Python UTF-8 `str`.
    void test_clock_set_timer_ns(CTestClock *clock,
                                 PyObject name,
                                 int64_t interval_ns,
                                 uint64_t start_time_ns,
                                 uint64_t stop_time_ns,
                                 Option_PyObject callback);

    PyObject test_clock_advance_time(CTestClock *clock, uint64_t to_time_ns);

    # Creates a logger from a valid Python object pointer and a defined logging level.
    #
    # # Safety
    # - `trader_id_ptr` must be borrowed from a valid Python UTF-8 `str`.
    # - `machine_id_ptr` must be borrowed from a valid Python UTF-8 `str`.
    # - `instance_id_ptr` must be borrowed from a valid Python UTF-8 `str`.
    CLogger logger_new(PyObject *trader_id_ptr,
                       PyObject *machine_id_ptr,
                       PyObject *instance_id_ptr,
                       LogLevel level_stdout,
                       uint8_t is_bypassed);

    void logger_free(CLogger logger);

    void flush(CLogger *logger);

    # Return the loggers trader ID.
    #
    # # Safety
    # - Assumes that since the data is originating from Rust, the GIL does not need
    # to be acquired.
    # - Assumes you are immediately returning this pointer to Python.
    PyObject *logger_get_trader_id(const CLogger *logger);

    # Return the loggers machine ID.
    #
    # # Safety
    # - Assumes that since the data is originating from Rust, the GIL does not need
    # to be acquired.
    # - Assumes you are immediately returning this pointer to Python.
    PyObject *logger_get_machine_id(const CLogger *logger);

    UUID4_t logger_get_instance_id(const CLogger *logger);

    uint8_t logger_is_bypassed(const CLogger *logger);

    # Log a message from valid Python object pointers.
    #
    # # Safety
    # - `component_ptr` must be borrowed from a valid Python UTF-8 `str`.
    # - `msg_ptr` must be borrowed from a valid Python UTF-8 `str`.
    void logger_log(CLogger *logger,
                    uint64_t timestamp_ns,
                    LogLevel level,
                    LogColor color,
                    PyObject *component_ptr,
                    PyObject *msg_ptr);
