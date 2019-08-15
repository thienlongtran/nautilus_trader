# -------------------------------------------------------------------------------------------------
# <copyright file="execution.pyx" company="Nautech Systems Pty Ltd">
#  Copyright (C) 2015-2019 Nautech Systems Pty Ltd. All rights reserved.
#  The use of this source code is governed by the license as found in the LICENSE.md file.
#  https://nautechsystems.io
# </copyright>
# -------------------------------------------------------------------------------------------------

import queue
import multiprocessing
import threading
import redis

from zmq import Context

from nautilus_trader.core.correctness cimport Condition
from nautilus_trader.core.message cimport MessageType, Message, Command, Event, Response
from nautilus_trader.model.commands cimport (
    AccountInquiry,
    SubmitOrder,
    SubmitAtomicOrder,
    CancelOrder,
    ModifyOrder)
from nautilus_trader.model.identifiers cimport TraderId
from nautilus_trader.model.events cimport OrderEvent, PositionEvent
from nautilus_trader.common.account cimport Account
from nautilus_trader.common.clock cimport LiveClock
from nautilus_trader.common.guid cimport LiveGuidFactory
from nautilus_trader.common.execution cimport ExecutionClient
from nautilus_trader.trade.portfolio cimport Portfolio
from nautilus_trader.network.workers import RequestWorker, SubscriberWorker
from nautilus_trader.serialization.base cimport CommandSerializer, ResponseSerializer, EventSerializer
from nautilus_trader.serialization.serializers cimport (
    MsgPackCommandSerializer,
    MsgPackResponseSerializer,
    MsgPackEventSerializer
)
from nautilus_trader.live.logger cimport LiveLogger
from nautilus_trader.serialization.serializers cimport EventSerializer, MsgPackEventSerializer


cdef class ExecutionDatabase:
    """
    Provides a process and thread safe execution database utilizing Redis.
    """

    def __init__(self,
                 TraderId trader_id,
                 int port=6379,
                 EventSerializer serializer=MsgPackEventSerializer()):
        """
        Initializes a new instance of the EventStore class.

        :param trader_id: The trader identifier.
        :param port: The redis port to connect to.
        :param serializer: The event serializer.
        :raises ConditionFailed: If the redis_port is not in range [0, 65535].
        """
        Condition.in_range(port, 'redis_port', 0, 65535)

        self._key_order_event = f'Nautilus:Traders:{trader_id.value}:Orders:'
        self._key_position_event = f'Nautilus:Traders:{trader_id.value}:Positions:'
        self._serializer = serializer
        self._redis = redis.StrictRedis(host='localhost', port=port, db=0)
        self._queue = multiprocessing.Queue()
        self._process = multiprocessing.Process(target=self._process_queue, daemon=True)
        self._process.start()

    cpdef void store(self, Event message):
        """
        Store the given event message.
        
        :param message: The event message to store.
        """
        self._queue.put(message)

    cpdef void _process_queue(self):
        # Process the queue one item at a time
        cdef Event event
        while True:
            event = self._queue.get()

            if isinstance(event, OrderEvent):
                self._store_order_event(event)
            elif isinstance(event, PositionEvent):
                self._store_position_event(event)

    cdef void _store_order_event(self, OrderEvent event):
        self._redis.rpush(self._key_order_event + event.order_id.value, self._serializer.serialize(event))

    cdef void _store_position_event(self, PositionEvent event):
        self._redis.rpush(self._key_position_event + event.position.id.value, self._serializer.serialize(event.order_fill))


cdef class LiveExecClient(ExecutionClient):
    """
    Provides an execution client for live trading utilizing a ZMQ transport
    to the execution service.
    """

    def __init__(
            self,
            zmq_context: Context,
            str service_name='NautilusExecutor',
            str service_address='localhost',
            str events_topic='NAUTILUS:EVENTS',
            int commands_port=55555,
            int events_port=55556,
            CommandSerializer command_serializer=MsgPackCommandSerializer(),
            ResponseSerializer response_serializer=MsgPackResponseSerializer(),
            EventSerializer event_serializer=MsgPackEventSerializer(),
            Account account=Account(),
            Portfolio portfolio=Portfolio(),
            LiveClock clock=LiveClock(),
            LiveGuidFactory guid_factory=LiveGuidFactory(),
            LiveLogger logger=LiveLogger(),
            ExecutionDatabase database=None):
        """
        Initializes a new instance of the LiveExecClient class.

        :param zmq_context: The ZMQ context.
        :param service_name: The name of the service.
        :param service_address: The execution service host IP address (default='localhost').
        :param events_topic: The execution service events topic (default='NAUTILUS:EXECUTION').
        :param commands_port: The execution service commands port (default=55555).
        :param events_port: The execution service events port (default=55556).
        :param command_serializer: The command serializer for the client.
        :param response_serializer: The response serializer for the client.
        :param event_serializer: The event serializer for the client.
        :param account: The account for the execution client.
        :param clock: The clock for the component.
        :param guid_factory: The GUID factory for the component.
        :param logger: The logger for the component (can be None).
        :param logger: The execution database for the component (can be None).
        :raises ConditionFailed: If the service_address is not a valid string.
        :raises ConditionFailed: If the events_topic is not a valid string.
        :raises ConditionFailed: If the commands_port is not in range [0, 65535].
        :raises ConditionFailed: If the events_port is not in range [0, 65535].
        """
        Condition.valid_string(service_address, 'service_address')
        Condition.valid_string(events_topic, 'events_topic')
        Condition.in_range(commands_port, 'commands_port', 0, 65535)
        Condition.in_range(events_port, 'events_port', 0, 65535)

        super().__init__(account,
                         portfolio,
                         clock,
                         guid_factory,
                         logger)
        self._zmq_context = zmq_context
        self._store = database
        self._queue = queue.Queue()
        self._thread = threading.Thread(target=self._process_queue, daemon=True)

        self._commands_worker = RequestWorker(
            f'{self.__class__.__name__}.CommandRequester',
            f'{service_name}.CommandRouter',
            service_address,
            commands_port,
            self._zmq_context,
            logger)

        self._events_worker = SubscriberWorker(
            f'{self.__class__.__name__}.EventSubscriber',
            f'{service_name}.EventsPublisher',
            service_address,
            events_port,
            self._zmq_context,
            self._event_handler,
            logger)

        self._command_serializer = command_serializer
        self._response_serializer = response_serializer
        self._event_serializer = event_serializer

        self.events_topic = events_topic
        self._thread.start()

    cpdef void connect(self):
        """
        Connect to the execution service.
        """
        self._events_worker.connect()
        self._commands_worker.connect()
        self._events_worker.subscribe(self.events_topic)

    cpdef void disconnect(self):
        """
        Disconnect from the execution service.
        """
        self._events_worker.unsubscribe(self.events_topic)
        self._commands_worker.disconnect()
        self._events_worker.disconnect()

    cpdef void check_residuals(self):
        """
        TBD.
        """
        self._check_residuals()

    cpdef void reset(self):
        """
        Resets the execution client by clearing all stateful internal values 
        and returning it to a fresh state.
        """
        self._reset()

    cpdef void dispose(self):
        """
        Disposes of the execution client.
        """
        self._commands_worker.dispose()
        self._events_worker.dispose()

    cpdef void execute_command(self, Command command):
        """
        Execute the given command by inserting it into the message bus for processing.
        
        :param command: The command to execute.
        """
        self._queue.put(command)

    cpdef void handle_event(self, Event event):
        """
        Handle the given event by inserting it into the message bus for processing.
        
        :param event: The event to handle
        """
        self._queue.put(event)

    cpdef void _process_queue(self):
        # Process the queue one item at a time
        cdef Message message
        while True:
            message = self._queue.get()

            if message.message_type == MessageType.EVENT:
                self._handle_event(message)
                if self._store is not None:  # TODO: Change this to calling a delegate
                    self._store.store(message)
            elif message.message_type == MessageType.COMMAND:
                self._execute_command(message)
            else:
                raise RuntimeError(f"Invalid message type on bus ({repr(message)}).")

    cdef void _account_inquiry(self, AccountInquiry command):
        self._command_handler(command)

    cdef void _submit_order(self, SubmitOrder command):
        self._command_handler(command)

    cdef void _submit_atomic_order(self, SubmitAtomicOrder command):
        self._command_handler(command)

    cdef void _modify_order(self, ModifyOrder command):
        self._command_handler(command)

    cdef void _cancel_order(self, CancelOrder command):
        self._command_handler(command)

    cdef void _command_handler(self, Command command):
        self._log.debug(f"Sending {command} ...")
        cdef bytes response_bytes = self._commands_worker.send(self._command_serializer.serialize(command))
        cdef Response response =  self._response_serializer.deserialize(response_bytes)
        self._log.debug(f"Received response {response}")

    cpdef void _event_handler(self, str topic, bytes event_bytes):
        cdef Event event = self._event_serializer.deserialize(event_bytes)
        self._handle_event(event)
