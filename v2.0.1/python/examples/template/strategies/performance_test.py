#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
    performance_test.py
    
    This test will measure how long it takes to open, modify and close pending 
    orders. It will open 100 pending orders and calculate the average durations. 
    Please don't run this on your live account. 
    The MT4 server must be initialized with MaximumOrders>=100. 
    
    IMPORTANT: The entry_price variable has to be below the current market 
    price of the symbol (EURUSD per default) as the script is using buy 
    limit orders.
        
    If there is an error while executing the open/modify/close commands, try 
    increasing the _delay variable. It is set to a very low value speed up 
    execution.
    
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
from threading import Thread, Lock
from time import sleep
from datetime import datetime, timedelta


#############################################################################
# Class derived from DWZ_ZMQ_Strategy includes data processor for PULL,SUB data
#############################################################################

class performance_test(DWX_ZMQ_Strategy):
    
    def __init__(self, 
                 symbol,
                 entry_price,
                 n,
                 _name="PERFORMANCE_TEST",
                 _delay=0.001,
                 _broker_gmt=3,
                 _verbose=False):
        
        # call DWX_ZMQ_Strategy constructor and passes itself as data processor for handling
        # received data on PULL and SUB ports 
        super().__init__(_name=_name,
                         _pulldata_handlers=[self],  # Registers itself as handler of pull data via self.onPullData()
                         _subdata_handlers=[self],   # Registers itself as handler of sub data via self.onSubData()
                         _verbose=_verbose)
        
        # This strategy's variables
        self._delay = _delay
        self._verbose = _verbose
        self._finished = False

        self.symbol = symbol
        self.entry_price = entry_price
        # number of orders to send.
        self.n = n

        self.before_open = datetime.utcnow()
        self.before_modification = datetime.utcnow()
        self.before_close = datetime.utcnow()
        self.open_duration = -100
        self.modify_duration = -100
        self.num_modifications = 0
        self.orders = []
        
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
        
        if data['_action'] == 'EXECUTION':
            self.orders.append({'_ticket': data['_ticket'], '_open_price': data['_open_price']})
            if len(self.orders) == self.n:
                self.open_duration = (datetime.utcnow() - self.before_open).total_seconds()
                self.modify_orders()
        elif data['_action'] == 'MODIFY':
            self.num_modifications += 1
            if self.num_modifications == self.n:
                self.modify_duration = (datetime.utcnow() - self.before_modification).total_seconds()
                self.close_orders()
        elif data['_action'] == 'CLOSE':
            self.orders = [trade for trade in self.orders if trade['_ticket'] != data['_ticket']]
        
        print('num orders:', len(self.orders), '| num_modifications:', self.num_modifications)
        
        if data['_action'] == 'CLOSE' and len(self.orders) == 0:
            close_duration = (datetime.utcnow() - self.before_close).total_seconds()
            print(f'\nopen_duration: {1000*self.open_duration/self.n:.1f} milliseconds per order')
            print(f'modify_duration: {1000*self.modify_duration/self.n:.1f} milliseconds per order')
            print(f'close_duration: {1000*close_duration/self.n:.1f} milliseconds per order')
            self.stop()
        
    ##########################################################################    
    def onSubData(self, data):        
        """
        Callback to process new data received through the SUB port
        """
        # split msg to get topic and message
        _topic, _msg = data.split(":|:")
        print('Data on Topic={} with Message={}'.format(_topic, _msg))
        
        
    ##########################################################################    
    def run(self):        
        """
        Starts price subscriptions
        """        
        self._finished = False

        # Subscribe to all symbols in self._symbols to receive bid,ask prices
        self.open_orders()

    ##########################################################################    
    def stop(self):
      """
      unsubscribe from all market symbols and exits
      """
      self._finished = True


    ##########################################################################
    def open_orders(self):
      """
      Opens self.n buy limit orders for symbol self.symbol at price self.entry_price.
      """
      
      self.before_open = datetime.utcnow()
      for i in range(self.n):
          try:
            # Acquire lock
            self._lock.acquire()
            trade = self._zmq._generate_default_order_dict()
            trade['_symbol'] = self.symbol
            trade['_type'] = 2  # buy limit
            trade['_price'] = self. entry_price
            trade['_SL'] = 0
            trade['_TP'] = 0
            print('open:', trade)
            self._zmq._DWX_MTX_NEW_TRADE_(trade)
              
          finally:
            # Release lock
            self._lock.release()        
            sleep(self._delay)


    def modify_orders(self):
        """
        Modifies all stored open orders to TP/SL of 100 points.
        """
    
        self.before_modification = datetime.utcnow()
        for trade in self.orders:
            try:
                # Acquire lock
                self._lock.acquire()
                print('modify:', trade)
                self._zmq._DWX_MTX_MODIFY_TRADE_BY_TICKET_(trade['_ticket'], 100, 100)

            finally:
                # Release lock
                self._lock.release()        
                sleep(self._delay)


    def close_orders(self):
        """
        Closes all stored open orders.
        """
        
        self.before_close = datetime.utcnow()
        for trade in self.orders:
            try:
                # Acquire lock
                self._lock.acquire()
                print('close:', trade)
                self._zmq._DWX_MTX_CLOSE_TRADE_BY_TICKET_(trade['_ticket'])

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
  
  # creates object with a given symbol, entry_price, and number of orders. 
  print('Loading example...')
  example = performance_test(symbol='EURUSD', entry_price=1.05, n=100)

  # Starts example execution
  print('unning example...')  
  example.run()

  # Waits example termination
  print('Waiting example termination...')
  while not example.isFinished():
    sleep(1)
    if (datetime.utcnow() > example.before_open + timedelta(minutes=1) and 
        (len(example.orders) != 0 or example.num_modifications != example.n)):
        print('num orders:', len(example.orders), '| num_modifications:', example.num_modifications)
        print("There was probably an error during execution. Try increasing the _delay variable.")
        example.stop()
  print('Bye!!!')
