#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
    feed_prices_and_rates.py
    
    An example using the Darwinex ZeroMQ Connector for Python 3 and MetaTrader 4 in
    which bid-ask price feed and OHLC rates are enabled, updated and disabled on real time. 

    -------------------
    Bid-Ask price feed:
    -------------------
    Through commmand TRACK_PRICES, this client can select multiple SYMBOLS for price tracking.
    For example, to receive real-time bid-ask prices from symbols EURUSD and GDAXI, this client
    will send this command to the Server, through its PUSH channel:

    "TRACK_PRICES;EURUSD;GDAXI"

    Server will answer through the PULL channel with a json response like this:

    {'_action':'TRACK_PRICES', '_data': {'symbol_count':2}}

    or if errors, then: 

    {'_action':'TRACK_PRICES', '_data': {'_response':'NOT_AVAILABLE'}}

    Once subscribed to this feed, it will receive through the SUB channel, prices in this format:
    "EURUSD BID;ASK"
    
    -------------------
    Rates feed:
    -------------------
    Through commmand TRACK_RATES, this client can select multiple INSTRUMENTS (symbol, timeframe).
    For example, to receive rates from instruments EURUSD(M1) and GDAXI(H1), this client
    will send this command to the Server, through its PUSH channel:

    "TRACK_RATES;EURUSD;1;GDAXI;60"

    Server will answer through the PULL channel with a json response like this:

    {'_action':'TRACK_RATES', '_data': {'instrument_count':2}}

    or if errors, then: 

    {'_action':'TRACK_RATES', '_data': {'_response':'NOT_AVAILABLE'}}

    Once subscribed to this feed, it will receive through the SUB channel, rates in this format:
    "EURUSD_M1 TIME;OPEN;HIGH;LOW;CLOSE;TICKVOL;SPREAD;REALVOL"
    "GDAXI_H1 TIME;OPEN;HIGH;LOW;CLOSE;TICKVOL;SPREAD;REALVOL"

    --
    
    @author: raulMrello
    
"""
# Append path for main project folder
import sys
import os

sys.path.append('../../..')
from examples.template.strategies.base.DWX_ZMQ_Strategy import DWX_ZMQ_Strategy

#############################################################################
#############################################################################

from pandas import Timedelta, to_datetime
from threading import Thread, Lock
from time import sleep
import random

class feed_prices_and_rates(DWX_ZMQ_Strategy):
    
    def __init__(self, 
                 _name="PRICES_RATES_FEED",
                 _symbols=['EURUSD'],
                 _instruments=[('EURUSD_M1', 'EURUSD', 1)],
                 _delay=0.1,
                 _broker_gmt=3,
                 _verbose=False):
        
        super().__init__(_name,
                         _symbols,
                         _broker_gmt,
                         [self],      # Registers itself as handler of pull data via self.onPullData
                         [self],      # Registers itself as handler of sub data via self.onSubData
                         _verbose)
        
        # This strategy's variables
        self._symbols = _symbols
        self._instruments = _instruments
        self._delay = _delay
        self._verbose = _verbose
        self._terminate = False
        
        # lock for acquire/release of ZeroMQ connector
        self._lock = Lock()
        
    ##########################################################################    
    def onPullData(self, data):        
        """
        Callback to process new data received through the PULL port
        """
        print('\rPULL_HANDLER received: {}'.format(data), end='', flush=True)
        
    ##########################################################################    
    def onSubData(self, data):        
        """
        Callback to process new data received through the SUB port
        """
        print('\rSUB_HANDLER received: {}'.format(data), end='', flush=True)
        
    ##########################################################################    
    def run(self):        
        """
        Logic:            
          1)  Creates a thread to log responses from server
          2)  Register symbols to get real-time price feeds
          3)  Register instruments to get rates feed
        """
        # 1)
        # _verbose can print too much information.. so let's start a thread
        # that prints an update for instructions flowing through ZeroMQ
        self._updater_ = Thread(name='Live_Updater',
                               target=self._updater_,
                               args=(self._delay,))
        self._updater_.daemon = True
        self._updater_.start()
        
        # 2)
        # Subscribe to all symbols in self._symbols to receive bid,ask prices
        self.__subscribe_to_price_feeds()

        # 3)
        # Subscribe to all instruments in self._instruments to receive OHLC rates
        self.__subscribe_to_rate_feeds()


    ##########################################################################    
    def stop(self):

      self._terminate = True

      # remove subscriptions and stop symbols price feeding
      try:
        # Acquire lock
        self._lock.acquire()
        self._zmq._DWX_MTX_UNSUBSCRIBE_ALL_MARKETDATA_REQUESTS_()
        print('\rUnsubscribing from all topics', end='', flush=True)
          
      finally:
        # Release lock
        self._lock.release()
        sleep(self._delay)
      
      try:
        # Acquire lock
        self._lock.acquire()
        self._zmq._DWX_MTX_SEND_TRACKPRICES_REQUEST_([])        
        print('\rRemoving symbols list', end='', flush=True)
        sleep(self._delay)
        self._zmq._DWX_MTX_SEND_TRACKRATES_REQUEST_([])
        print('\rRemoving instruments list', end='', flush=True)

      finally:
        # Release lock
        self._lock.release()
        sleep(self._delay)

      # Kill the updater thread
      self._updater_.join()
      
      print('\n\n{} .. wait for me.... I\'m going home! xD\n'.format(self._updater_.getName()))


    ##########################################################################
    def __subscribe_to_price_feeds(self):
      if len(self._symbols) > 0:
        # subscribe to all symbols price feeds
        for _symbol in self._symbols:
          try:
            # Acquire lock
            self._lock.acquire()
            self._zmq._DWX_MTX_SUBSCRIBE_MARKETDATA_(_symbol, _string_delimiter=';')
            print('\rSubscribed to {} price feed'.format(_symbol), end='', flush=True)
              
          finally:
            # Release lock
            self._lock.release()        
            sleep(self._delay)

        # configure symbols to receive price feeds        
        try:
          # Acquire lock
          self._lock.acquire()
          self._zmq._DWX_MTX_SEND_TRACKPRICES_REQUEST_(self._symbols)
          print('\rConfiguring price feed for {} symbols'.format(len(self._symbols)), end='', flush=True)
            
        finally:
          # Release lock
          self._lock.release()
          sleep(self._delay)      

              
    ##########################################################################
    def __subscribe_to_rate_feeds(self):
      if len(self._instruments) > 0:
        # subscribe to all instruments' rate feeds
        for _instrument in self._instruments:
          try:
            # Acquire lock
            self._lock.acquire()
            self._zmq._DWX_MTX_SUBSCRIBE_MARKETDATA_(_instrument[0], _string_delimiter=';')
            print('\rSubscribed to {} rate feed'.format(_instrument), end='', flush=True)
              
          finally:
            # Release lock
            self._lock.release()        
          sleep(self._delay)

        # configure instruments to receive price feeds
        try:
          # Acquire lock
          self._lock.acquire()
          self._zmq._DWX_MTX_SEND_TRACKRATES_REQUEST_(self._instruments)
          print('\rConfiguring rate feed for {} instruments'.format(len(self._instruments)), end='', flush=True)
            
        finally:
          # Release lock
          self._lock.release()
          sleep(self._delay)    


    ##########################################################################
    def _updater_(self, _delay=0.1):
        
        while not self._terminate:            
          try:
            # Acquire lock
            self._lock.acquire()
            # read response command
            _txt = str(self._zmq._get_response_())
            if _txt != 'None':                
              # clear response buffer
              self._zmq._set_response_()            
              print('\r{}'.format(_txt), end='', flush=True)
              
          finally:
            # Release lock
            self._lock.release()
      
          sleep(self._delay)



""" -----------------------------------------------------------------------------------------------
    -----------------------------------------------------------------------------------------------
    INICIO DEL SCRIPT
    -----------------------------------------------------------------------------------------------
    -----------------------------------------------------------------------------------------------
"""
if __name__ == "__main__":
  print("Loading example...")
  example = feed_prices_and_rates()    
  print('Running example...')
  example.run()
  print('\rWaiting forever...')
  while True:
    sleep(1)
