# -*- coding: utf-8 -*-

"""
    DWX_ZeroMQ_Connector_v2_0_2_RC8.py
    --
    @author: Darwinex Labs (www.darwinex.com)
    
    Copyright (c) 2017-2019, Darwinex. All rights reserved.
    
    Licensed under the BSD 3-Clause License, you may not use this file except 
    in compliance with the License. 
    
    You may obtain a copy of the License at:    
    https://opensource.org/licenses/BSD-3-Clause
"""

# IMPORT zmq library
# import zmq, time
import zmq
from time import sleep
from pandas import DataFrame, Timestamp
from threading import Thread

class DWX_ZeroMQ_Connector():

    """
    Setup ZeroMQ -> MetaTrader Connector
    """
    def __init__(self, 
                 _ClientID='DLabs_Python',  # Unique ID for this client
                 _host='localhost',         # Host to connect to
                 _protocol='tcp',           # Connection protocol
                 _PUSH_PORT=32768,           # Port for Sending commands
                 _PULL_PORT=32769,           # Port for Receiving responses
                 _SUB_PORT=32770,            # Port for Subscribing for prices
                 _delimiter=';',
                 _pulldata_handlers = [],    # Handlers to process data received through PULL port.
                 _subdata_handlers = [],     # Handlers to process data received through SUB port.
                 _verbose=False):           # String delimiter           
    
        # Strategy Status (if this is False, ZeroMQ will not listen for data)
        self._ACTIVE = True
        
        # Client ID
        self._ClientID = _ClientID
        
        # ZeroMQ Host
        self._host = _host
        
        # Connection Protocol
        self._protocol = _protocol

        # ZeroMQ Context
        self._ZMQ_CONTEXT = zmq.Context()
        
        # TCP Connection URL Template
        self._URL = self._protocol + "://" + self._host + ":"
        
        # Ports for PUSH, PULL and SUB sockets respectively
        self._PUSH_PORT = _PUSH_PORT
        self._PULL_PORT = _PULL_PORT
        self._SUB_PORT = _SUB_PORT

        # Handlers for received data (pull and sub ports)
        self._pulldata_handlers = _pulldata_handlers
        self._subdata_handlers = _subdata_handlers
        
        # Create Sockets
        self._PUSH_SOCKET = self._ZMQ_CONTEXT.socket(zmq.PUSH)
        self._PUSH_SOCKET.setsockopt(zmq.SNDHWM, 1)
        
        self._PULL_SOCKET = self._ZMQ_CONTEXT.socket(zmq.PULL)
        self._PULL_SOCKET.setsockopt(zmq.RCVHWM, 1)
        
        self._SUB_SOCKET = self._ZMQ_CONTEXT.socket(zmq.SUB)
        
        # Bind PUSH Socket to send commands to MetaTrader
        self._PUSH_SOCKET.connect(self._URL + str(self._PUSH_PORT))
        print("[INIT] Ready to send commands to METATRADER (PUSH): " + str(self._PUSH_PORT))
        
        # Connect PULL Socket to receive command responses from MetaTrader
        self._PULL_SOCKET.connect(self._URL + str(self._PULL_PORT))
        print("[INIT] Listening for responses from METATRADER (PULL): " + str(self._PULL_PORT))
        
        # Connect SUB Socket to receive market data from MetaTrader
        self._SUB_SOCKET.connect(self._URL + str(self._SUB_PORT))
        
        # Initialize POLL set and register PULL and SUB sockets
        self._poller = zmq.Poller()
        self._poller.register(self._PULL_SOCKET, zmq.POLLIN)
        self._poller.register(self._SUB_SOCKET, zmq.POLLIN)
        
        # Start listening for responses to commands and new market data
        self._string_delimiter = _delimiter
        
        # BID/ASK Market Data Subscription Threads ({SYMBOL: Thread})
        self._MarketData_Thread = None
        
        # Begin polling for PULL / SUB data
        self._MarketData_Thread = Thread(target=self._DWX_ZMQ_Poll_Data_, args=(self._string_delimiter))
        self._MarketData_Thread.start()
        
        # Market Data Dictionary by Symbol (holds tick data) or Instrument (holds OHLC data)
        self._Market_Data_DB = {}   # {SYMBOL: {TIMESTAMP: (BID, ASK)}}
                                    # {SYMBOL: {TIMESTAMP: (TIME, OPEN, HIGH, LOW, CLOSE, TICKVOL, SPREAD, VOLUME)}}

        # Temporary Order STRUCT for convenience wrappers later.
        self.temp_order_dict = self._generate_default_order_dict()
        
        # Thread returns the most recently received DATA block here
        self._thread_data_output = None
        
        # Verbosity
        self._verbose = _verbose
        
    ##########################################################################
    
    """
    Set Status (to enable/disable strategy manually)
    """
    def _setStatus(self, _new_status=False):
    
        self._ACTIVE = _new_status
        print("\n**\n[KERNEL] Setting Status to {} - Deactivating Threads.. please wait a bit.\n**".format(_new_status))
                
    ##########################################################################
    
    """
    Function to send commands to MetaTrader (PUSH)
    """
    def remote_send(self, _socket, _data):
        
        try:
            _socket.send_string(_data, zmq.DONTWAIT)
        except zmq.error.Again:
            print("\nResource timeout.. please try again.")
            sleep(0.000000001)
      
    ##########################################################################
    
    def _get_response_(self):
        return self._thread_data_output
    
    ##########################################################################
    
    def _set_response_(self, _resp=None):
        self._thread_data_output = _resp
    
    ##########################################################################
    
    def _valid_response_(self, _input='zmq'):
        
        # Valid data types
        _types = (dict,DataFrame)
        
        # If _input = 'zmq', assume self._zmq._thread_data_output
        if isinstance(_input, str) and _input == 'zmq':
            return isinstance(self._get_response_(), _types)
        else:
            return isinstance(_input, _types)
            
        # Default
        return False
    
    ##########################################################################
    
    """
    Function to retrieve data from MetaTrader (PULL or SUB)
    """
    def remote_recv(self, _socket):
        
        try:
            msg = _socket.recv_string(zmq.DONTWAIT)
            return msg
        except zmq.error.Again:
            print("\nResource timeout.. please try again.")
            sleep(0.000001)
            
        return None
        
    ##########################################################################
    
    # Convenience functions to permit easy trading via underlying functions.
    
    # OPEN ORDER
    def _DWX_MTX_NEW_TRADE_(self, _order=None):
        
        if _order is None:
            _order = self._generate_default_order_dict()
        
        # Execute
        self._DWX_MTX_SEND_COMMAND_(**_order)
        
    # MODIFY ORDER
    def _DWX_MTX_MODIFY_TRADE_BY_TICKET_(self, _ticket, _SL, _TP): # in points
        
        try:
            self.temp_order_dict['_action'] = 'MODIFY'
            self.temp_order_dict['_SL'] = _SL
            self.temp_order_dict['_TP'] = _TP
            self.temp_order_dict['_ticket'] = _ticket
            
            # Execute
            self._DWX_MTX_SEND_COMMAND_(**self.temp_order_dict)
            
        except KeyError:
            print("[ERROR] Order Ticket {} not found!".format(_ticket))
    
    # CLOSE ORDER
    def _DWX_MTX_CLOSE_TRADE_BY_TICKET_(self, _ticket):
        
        try:
            self.temp_order_dict['_action'] = 'CLOSE'
            self.temp_order_dict['_ticket'] = _ticket
            
            # Execute
            self._DWX_MTX_SEND_COMMAND_(**self.temp_order_dict)
            
        except KeyError:
            print("[ERROR] Order Ticket {} not found!".format(_ticket))
            
    # CLOSE PARTIAL
    def _DWX_MTX_CLOSE_PARTIAL_BY_TICKET_(self, _ticket, _lots):
        
        try:
            self.temp_order_dict['_action'] = 'CLOSE_PARTIAL'
            self.temp_order_dict['_ticket'] = _ticket
            self.temp_order_dict['_lots'] = _lots
            
            # Execute
            self._DWX_MTX_SEND_COMMAND_(**self.temp_order_dict)
            
        except KeyError:
            print("[ERROR] Order Ticket {} not found!".format(_ticket))
            
    # CLOSE MAGIC
    def _DWX_MTX_CLOSE_TRADES_BY_MAGIC_(self, _magic):
        
        try:
            self.temp_order_dict['_action'] = 'CLOSE_MAGIC'
            self.temp_order_dict['_magic'] = _magic
            
            # Execute
            self._DWX_MTX_SEND_COMMAND_(**self.temp_order_dict)
            
        except KeyError:
            pass
    
    # CLOSE ALL TRADES
    def _DWX_MTX_CLOSE_ALL_TRADES_(self):
        
        try:
            self.temp_order_dict['_action'] = 'CLOSE_ALL'
            
            # Execute
            self._DWX_MTX_SEND_COMMAND_(**self.temp_order_dict)
            
        except KeyError:
            pass
        
    # GET OPEN TRADES
    def _DWX_MTX_GET_ALL_OPEN_TRADES_(self):
        
        try:
            self.temp_order_dict['_action'] = 'GET_OPEN_TRADES'
                        
            # Execute
            self._DWX_MTX_SEND_COMMAND_(**self.temp_order_dict)
            
        except KeyError:
            pass
    
    # DEFAULT ORDER DICT
    def _generate_default_order_dict(self):
        return({'_action': 'OPEN',
                  '_type': 0,
                  '_symbol': 'EURUSD',
                  '_price': 0.0,
                  '_SL': 500, # SL/TP in POINTS, not pips.
                  '_TP': 500,
                  '_comment': 'DWX_Python_to_MT',
                  '_lots': 0.01,
                  '_magic': 123456,
                  '_ticket': 0})
    
    # DEFAULT DATA REQUEST DICT
    def _generate_default_data_dict(self):
        return({'_action': 'DATA',
                  '_symbol': 'EURUSD',
                  '_timeframe': 1440, # M1 = 1, M5 = 5, and so on..
                  '_start': '2018.12.21 17:00:00', # timestamp in MT4 recognized format
                  '_end': '2018.12.21 17:05:00'})
    
    # DEFAULT HIST REQUEST DICT
    def _generate_default_hist_dict(self):
        return({'_action': 'HIST',
                  '_symbol': 'EURUSD',
                  '_timeframe': 1, # M1 = 1, M5 = 5, and so on..
                  '_start': '2018.12.21 17:00:00', # timestamp in MT4 recognized format
                  '_end': '2018.12.21 17:05:00'})
        
    ##########################################################################
    """
    Function to construct messages for sending DATA commands to MetaTrader
    """
    def _DWX_MTX_SEND_MARKETDATA_REQUEST_(self,
                                 _symbol='EURUSD',
                                 _timeframe=1,
                                 _start='2019.01.04 17:00:00',
                                 _end=Timestamp.now().strftime('%Y.%m.%d %H:%M:00')):
                                 #_end='2019.01.04 17:05:00'):
        
        _msg = "{};{};{};{};{}".format('DATA',
                                     _symbol,
                                     _timeframe,
                                     _start,
                                     _end)
        # Send via PUSH Socket
        self.remote_send(self._PUSH_SOCKET, _msg)
    
    
    ##########################################################################
    """
    Function to construct messages for sending HIST commands to MetaTrader
    """
    def _DWX_MTX_SEND_MARKETHIST_REQUEST_(self,
                                 _symbol='EURUSD',
                                 _timeframe=1,
                                 _start='2019.01.04 17:00:00',
                                 _end=Timestamp.now().strftime('%Y.%m.%d %H:%M:00')):
                                 #_end='2019.01.04 17:05:00'):
        
        _msg = "{};{};{};{};{}".format('HIST',
                                     _symbol,
                                     _timeframe,
                                     _start,
                                     _end)
        # Send via PUSH Socket
        self.remote_send(self._PUSH_SOCKET, _msg)
    
    
    ##########################################################################
    """
    Function to construct messages for sending TRACK_PRICES commands to MetaTrader
    """
    def _DWX_MTX_SEND_TRACKPRICES_REQUEST_(self,
                                 _symbols=['EURUSD']):
        _msg = 'TRACK_PRICES'                                 
        for s in _symbols:
          _msg = _msg + ";{}".format(s)

        # Send via PUSH Socket
        self.remote_send(self._PUSH_SOCKET, _msg)
    
    
    ##########################################################################
    """
    Function to construct messages for sending TRACK_RATES commands to MetaTrader
    """
    def _DWX_MTX_SEND_TRACKRATES_REQUEST_(self,
                                 _instruments=[('EURUSD_M1','EURUSD',1)]):
        _msg = 'TRACK_RATES'                                 
        for i in _instruments:
          _msg = _msg + ";{};{}".format(i[1],i[2])
          
        # Send via PUSH Socket
        self.remote_send(self._PUSH_SOCKET, _msg)
    
    
    ##########################################################################
    """
    Function to construct messages for sending Trade commands to MetaTrader
    """
    def _DWX_MTX_SEND_COMMAND_(self, _action='OPEN', _type=0,
                                 _symbol='EURUSD', _price=0.0,
                                 _SL=50, _TP=50, _comment="Python-to-MT",
                                 _lots=0.01, _magic=123456, _ticket=0):
        
        _msg = "{};{};{};{};{};{};{};{};{};{};{}".format('TRADE',_action,_type,
                                                         _symbol,_price,
                                                         _SL,_TP,_comment,
                                                         _lots,_magic,
                                                         _ticket)
        
        # Send via PUSH Socket
        self.remote_send(self._PUSH_SOCKET, _msg)
        
        """
         compArray[0] = TRADE or DATA
         compArray[1] = ACTION (e.g. OPEN, MODIFY, CLOSE)
         compArray[2] = TYPE (e.g. OP_BUY, OP_SELL, etc - only used when ACTION=OPEN)
         
         For compArray[0] == DATA, format is: 
             DATA|SYMBOL|TIMEFRAME|START_DATETIME|END_DATETIME
         
         // ORDER TYPES: 
         // https://docs.mql4.com/constants/tradingconstants/orderproperties
         
         // OP_BUY = 0
         // OP_SELL = 1
         // OP_BUYLIMIT = 2
         // OP_SELLLIMIT = 3
         // OP_BUYSTOP = 4
         // OP_SELLSTOP = 5
         
         compArray[3] = Symbol (e.g. EURUSD, etc.)
         compArray[4] = Open/Close Price (ignored if ACTION = MODIFY)
         compArray[5] = SL
         compArray[6] = TP
         compArray[7] = Trade Comment
         compArray[8] = Lots
         compArray[9] = Magic Number
         compArray[10] = Ticket Number (MODIFY/CLOSE)
         """
        # pass
    
    ##########################################################################
    
    """
    Function to check Poller for new reponses (PULL) and market data (SUB)
    """
    
    def _DWX_ZMQ_Poll_Data_(self, 
                           string_delimiter=';'):
        
        while self._ACTIVE:
            
            sockets = dict(self._poller.poll())
            
            # Process response to commands sent to MetaTrader
            if self._PULL_SOCKET in sockets and sockets[self._PULL_SOCKET] == zmq.POLLIN:
                
                try:
                    
                    msg = self._PULL_SOCKET.recv_string(zmq.DONTWAIT)
                    
                    # If data is returned, store as pandas Series
                    if msg != '' and msg != None:
                        
                        try: 
                            _data = eval(msg)
                            
                            self._thread_data_output = _data
                            if self._verbose:
                              print(_data) # default logic
                            # invokes data handlers on pull port
                            for hnd in self._pulldata_handlers:
                              hnd.onPullData(_data)
                                
                        except Exception as ex:
                            _exstr = "Exception Type {0}. Args:\n{1!r}"
                            _msg = _exstr.format(type(ex).__name__, ex.args)
                            print(_msg)
               
                except zmq.error.Again:
                    pass # resource temporarily unavailable, nothing to print
                except ValueError:
                    pass # No data returned, passing iteration.
                except UnboundLocalError:
                    pass # _symbol may sometimes get referenced before being assigned.
            
            # Receive new market data from MetaTrader
            if self._SUB_SOCKET in sockets and sockets[self._SUB_SOCKET] == zmq.POLLIN:
                
                try:
                  msg = self._SUB_SOCKET.recv_string(zmq.DONTWAIT)
                  
                  if msg != "":
                    _timestamp = str(Timestamp.now('UTC'))[:-6]
                    _symbol, _data = msg.split(" ")
                    if len(_data.split(string_delimiter)) == 2:
                      _bid, _ask = _data.split(string_delimiter)
                      if self._verbose:
                        print("\n[" + _symbol + "] " + _timestamp + " (" + _bid + "/" + _ask + ") BID/ASK")                    
                      # Update Market Data DB
                      if _symbol not in self._Market_Data_DB.keys():
                        self._Market_Data_DB[_symbol] = {}
                      self._Market_Data_DB[_symbol][_timestamp] = (float(_bid), float(_ask))

                    elif len(_data.split(string_delimiter)) == 8:
                      _time, _open, _high, _low, _close, _tick_vol, _spread, _real_vol = _data.split(string_delimiter)
                      if self._verbose:
                        print("\n[" + _symbol + "] " + _timestamp + " (" + _time + "/" + _open + "/" + _high + "/" + _low + "/" + _close + "/" + _tick_vol + "/" + _spread + "/" + _real_vol + ") TIME/OPEN/HIGH/LOW/CLOSE/TICKVOL/SPREAD/VOLUME")                    
                      # Update Market Rate DB
                      if _symbol not in self._Market_Data_DB.keys():
                        self._Market_Data_DB[_symbol] = {}
                      self._Market_Data_DB[_symbol][_timestamp] = (int(_time), float(_open), float(_high), float(_low), float(_close), int(_tick_vol), int(_spread), int(_real_vol))
                    # invokes data handlers on sub port
                    for hnd in self._subdata_handlers:
                      hnd.onSubData(msg)                      
                   
                except zmq.error.Again:
                    pass # resource temporarily unavailable, nothing to print
                except ValueError:
                    pass # No data returned, passing iteration.
                except UnboundLocalError:
                    pass # _symbol may sometimes get referenced before being assigned.
                
    ##########################################################################
    
    """
    Function to subscribe to given Symbol's BID/ASK feed from MetaTrader
    """
    def _DWX_MTX_SUBSCRIBE_MARKETDATA_(self, _symbol, _string_delimiter=';'):
        
        # Subscribe to SYMBOL first.
        self._SUB_SOCKET.setsockopt_string(zmq.SUBSCRIBE, _symbol)
        
        if self._MarketData_Thread is None:
            
            self._MarketData_Thread = Thread(target=self._DWX_ZMQ_Poll_Data, args=(_string_delimiter))
            self._MarketData_Thread.start()
        
        print("[KERNEL] Subscribed to {} MARKET updates. See self._Market_Data_DB.".format(_symbol))
    
    """
    Function to unsubscribe to given Symbol's BID/ASK feed from MetaTrader
    """
    def _DWX_MTX_UNSUBSCRIBE_MARKETDATA_(self, _symbol):
        
        self._SUB_SOCKET.setsockopt_string(zmq.UNSUBSCRIBE, _symbol)
        print("\n**\n[KERNEL] Unsubscribing from " + _symbol + "\n**\n")
        
        
    """
    Function to unsubscribe from ALL MetaTrader Symbols
    """
    def _DWX_MTX_UNSUBSCRIBE_ALL_MARKETDATA_REQUESTS_(self):
        
        self._setStatus(False)
        self._MarketData_Thread = None
    
    ##########################################################################
