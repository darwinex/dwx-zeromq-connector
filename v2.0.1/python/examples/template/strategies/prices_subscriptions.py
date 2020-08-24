#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
    prices_subscriptions.py
    
    An example of using the Darwinex ZeroMQ Connector for Python 3 and MetaTrader 4 PULL REQUEST
    for v2.0.1 in which a Client modifies symbol list configured in the EA to get bid-ask prices 
    from EURUSD and GDAXI. When it receives 10 prices from each feed, it will cancel GDAXI feed 
    and only receives 10 more prices from EURUSD. 

    Once received those next 10 prices, it cancels all prices feeds. After 30 seconds, the program 
    finishes.

    The Client will register a data processor in ZMQ-Connector to be notified when new data arrives
    through the PULL and SUB ports.

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
        
    --
    
    @author: [raulMrello](https://www.linkedin.com/in/raul-martin-19254530/)
    
"""


#############################################################################
# DWX-ZMQ required imports 
#############################################################################


# Append path for main project folder
import sys
sys.path.append('../../..')

# Import ZMQ-Strategy from relative path
from examples.template.strategies.base.DWX_ZMQ_Strategy import DWX_ZMQ_Strategy


#############################################################################
# Other required imports
#############################################################################

import os
from pandas import Timedelta, to_datetime
from threading import Thread, Lock
from time import sleep
import random


#############################################################################
# Class derived from DWZ_ZMQ_Strategy includes data processor for PULL,SUB data
#############################################################################

class prices_subscriptions(DWX_ZMQ_Strategy):
    
    def __init__(self, 
                 _name="PRICES_SUBSCRIPTIONS",
                 _symbols=['EURUSD','GDAXI'],
                 _delay=0.1,
                 _broker_gmt=3,
                 _verbose=False):
        
        # call DWX_ZMQ_Strategy constructor and passes itself as data processor for handling
        # received data on PULL and SUB ports 
        super().__init__(_name,
                         _symbols,
                         _broker_gmt,
                         [self],      # Registers itself as handler of pull data via self.onPullData()
                         [self],      # Registers itself as handler of sub data via self.onSubData()
                         _verbose)
        
        # This strategy's variables
        self._symbols = _symbols
        self._delay = _delay
        self._verbose = _verbose
        self._finished = False

        # Initializes counters of number of prices received from each symbol
        self._eurusd_cnt = 0
        self._gdaxi_cnt  = 0
        
        # lock for acquire/release of ZeroMQ connector
        self._lock = Lock()
        
    ##########################################################################    
    def isFinished(self):        
        """ Check if execution finished"""
        return self._finished
        
    ##########################################################################    
    def onPullData(self, data):        
        """
        Callback to process new data received through the PULL port
        """        
        # print responses to request commands
        print('Response from ExpertAdvisor={}'.format(data))
        
    ##########################################################################    
    def onSubData(self, data):        
        """
        Callback to process new data received through the SUB port
        """
        # split msg to get topic and message
        _topic, _msg = data.split(" ")
        print('Data on Topic={} with Message={}'.format(_topic, _msg))

        # increment counters
        if _topic == 'EURUSD':
          self._eurusd_cnt += 1
        if _topic == 'GDAXI':
          self._gdaxi_cnt += 1

        # check if received at least 10 prices from each and then cancel GDAXI feed
        if self._eurusd_cnt >= 10 and self._gdaxi_cnt >= 10:
          # updates the symbol list and request the update to the Expert Advisor
          self._symbols = ['EURUSD']
          self.__subscribe_to_price_feeds()
          # resets counters
          self._eurusd_cnt = 0
          self._gdaxi_cnt = 0

        # check if received 10 more prices from EURUSD with GDAXI disabled
        if self._eurusd_cnt >= 10 and len(self._symbols) == 1:
          # finishes (removes all subscriptions)  
          self.stop()
        
        
    ##########################################################################    
    def run(self):        
        """
        Starts price subscriptions
        """        
        self._finished = False

        # Subscribe to all symbols in self._symbols to receive bid,ask prices
        self.__subscribe_to_price_feeds()

    ##########################################################################    
    def stop(self):
      """
      unsubscribe from all market symbols and exits
      """
        
      # remove subscriptions and stop symbols price feeding
      try:
        # Acquire lock
        self._lock.acquire()
        self._zmq._DWX_MTX_UNSUBSCRIBE_ALL_MARKETDATA_REQUESTS_()
        print('Unsubscribing from all topics')
          
      finally:
        # Release lock
        self._lock.release()
        sleep(self._delay)
      
      try:
        # Acquire lock
        self._lock.acquire()
        self._zmq._DWX_MTX_SEND_TRACKPRICES_REQUEST_([])        
        print('Removing symbols list')
        sleep(self._delay)
        self._zmq._DWX_MTX_SEND_TRACKRATES_REQUEST_([])
        print('Removing instruments list')

      finally:
        # Release lock
        self._lock.release()
        sleep(self._delay)

      self._finished = True


    ##########################################################################
    def __subscribe_to_price_feeds(self):
      """
      Starts the subscription to the self._symbols list setup during construction.
      1) Setup symbols in Expert Advisor through self._zmq._DWX_MTX_SUBSCRIBE_MARKETDATA_
      2) Starts price feeding through self._zmq._DWX_MTX_SEND_TRACKPRICES_REQUEST_
      """
      if len(self._symbols) > 0:
        # subscribe to all symbols price feeds
        for _symbol in self._symbols:
          try:
            # Acquire lock
            self._lock.acquire()
            self._zmq._DWX_MTX_SUBSCRIBE_MARKETDATA_(_symbol)
            print('Subscribed to {} price feed'.format(_symbol))
              
          finally:
            # Release lock
            self._lock.release()        
            sleep(self._delay)

        # configure symbols to receive price feeds        
        try:
          # Acquire lock
          self._lock.acquire()
          self._zmq._DWX_MTX_SEND_TRACKPRICES_REQUEST_(self._symbols)
          print('Configuring price feed for {} symbols'.format(len(self._symbols)))
            
        finally:
          # Release lock
          self._lock.release()
          sleep(self._delay)      


""" -----------------------------------------------------------------------------------------------
    -----------------------------------------------------------------------------------------------
    SCRIPT SETUP
    -----------------------------------------------------------------------------------------------
    -----------------------------------------------------------------------------------------------
"""
if __name__ == "__main__":
  
  # creates object with a predefined configuration: symbol list including EURUSD and GDAXI
  print('Loading example...')
  example = prices_subscriptions()  

  # Starts example execution
  print('unning example...')  
  example.run()

  # Waits example termination
  print('Waiting example termination...')
  while not example.isFinished():
    sleep(1)
  print('Bye!!!')
