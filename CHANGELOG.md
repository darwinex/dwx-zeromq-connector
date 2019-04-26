# DWX ZeroMQ Connector  { Python 3 to MetaTrader 4 }

# Pull-request for version: 2.0.2 [(here)](https://github.com/raulMrello/dwx-zeromq-connector)

## Table of Contents
* [Introduction](#introduction)
* [New PUSH commands from Client side](#new-push-commands)
* [Configuration](#configuration)
* [Example Usage](#example-usage)
* [Video Tutorials](#video-tutorials)
* [Complete list of available functions](#available-functions)
* [License](#license) 

## Introduction
Playing with this project during some time, I miss some important features like:

- Clients in current version, only can do subscriptions to prices (bid-ask) from a list of symbols configured in the Expert Advisor, but they can not update this list during runtime. With this update, clients can modify the symbol list managed by the Expert Advisor  through a new PUSH request, at any time.

- Clients in current version can not subscribe to MqlRates (OHLC bars) from an instrument (an instrument can be seen as a tuple of symbol and timeframe parameters, for example EURUSD at M1). With this update, clients can setup the instrument list managed by the Expert Advisor, through a new PUSH request, at any time, and receive their rates at each corresponding pace.
  
- In current version, ZMQ Connector updates dictionary 'self._Market_Data_DB' when new data is received, and clients must check it periodically. With this update, the connector is modified, allowing the installation of two callbacks (one for PULL socket and the other for SUB socket). Callbacks will be invoked when new data is available at the associated socket. So, clients now can operate in a more optimized way, by using the event-driven framework provided by the callbacks.
  
- Current version doesn't provide a mechanism, so that clients can request a historic of MqlRates from a given instrument. With this update a new PUSH request is developed for that purpose.


## New PUSH commands from Client side

Along this section I will explain new functionalities commented previously.

### PUSH request to change the list of symbols whose prices are published from the Expert Advisor

This request is identified by the command: 'TRACK_PRICES' and its format is as follows:

```TRACK_PRICES;SYMBOL_1;SYMBOL_2;SYMBOL_3;.....;SYMBOL_N```

For example, to start receiving bid-ask prices from EURUSD, GDAXI and EURGBP, clients can send this PUSH request to the Server side:

```TRACK_PRICES;EURUSD;GDAXI;EURGBP```

At any given time, clients can cancel EURUSD prices feed, updating that list with this new PUSH request:

```TRACK_PRICES;GDAXI;EURGBP```

Also, clientes can stop any prices feed with this PUSH request:

```TRACK_PRICES```

Note: Clients will receive a message (bid-ask price) for each subscribed symbol.

In order to provide this new functionality a new method is added to the connector:

```cpp
def _DWX_MTX_SEND_TRACKPRICES_REQUEST_(self,_symbols=['EURUSD'])
```

### PUSH request to change the list of instruments whose MqlRates are published from the Expert Advisor

This request is identified by the command: 'TRACK_RATES' and its format is as follows:

```TRACK_RATES;SYMBOL_1;TIMEFRAME_1;SYMBOL_2;TIMEFRAME_2;.....;SYMBOL_N;TIMEFRAME_N```

For example, to start receiving MqlRates(time-open-high-low-close-tickvol-spread-realvol) from EURUSD at timeframe M1, and GDAXI at timeframe H4, clients can send this PUSH request to the Server side:

```TRACK_RATES;EURUSD;1;GDAXI;240```

Note: H4 = 4hours = 4*60mins = 240mins (timeframe = 240)

This list can be changed at any given time. As before, clients cand stop any MqlRates feed by sending this PUSH resquest:

```TRACK_RATES```

In order to provide this new functionality a new method is added to the connector:

```cpp
def _DWX_MTX_SEND_TRACKRATES_REQUEST_(self,_instruments=[('EURUSD_M1','EURUSD',1)]):
```    
Note: Instruments are tuples of 3 parameters (name, symbol, timeframe). In this case, name is formed with this format: ```SYMBOL_TIMEFRAME```, where ```TIMEFRAME``` can holds values associated with standard timeframes: ```M1,M5,M15,M30,H1,H4,D1,W1,MN1```

### PUSH request to receive MqlRate historic from a given instrument

In this case, the PUSH request follows this format (the same as ```DATA``` request):

```HIST;SYMBOL;TIMEFRAME;START_TIME;END_TIME```

This functionality is provided by this new method:

```cpp
def _DWX_MTX_SEND_MARKETHIST_REQUEST_(self,
                                 _symbol='EURUSD',
                                 _timeframe=1,
                                 _start='2019.01.04 17:00:00',
                                 _end=Timestamp.now().strftime('%Y.%m.%d %H:%M:00')):
```

### Callbacks for new PULL,SUB data arrived notifications

In this case, ZMQ Connector is modified providing on its constructor, two lists of handlers that must be notified when new data arrives:

- ```_pulldata_handlers```: is a list of handlers that will be notified when new data arrives through the PULL port, calling to their public method ```handler.onPullData(new_data)```.

- ```_subdata_handlers```: is a list of handlers that will be notified when new data arrives through the SUB port, calling to their public method ```handler.onSubData(new_data)```.

The Connector's constructor is redesigned as follows:

```cpp
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
```

A common implementation of a handler that can get notifications from both sockets could be:

```cpp
class Handler():
    """ Handles PULL socket data """
    def onPullData(self, new_data):
        print('Received new data on PULL socket ={}'.format(new_data))

    """ Handles SUB socket data """
    def onSubData(self, new_data):
        print('Received new data on SUB socket ={}'.format(new_data))   
```

And then a given client, could start ZMQ connector installing these handlers, in this way:


```cpp
hnd = Handler()
DWX_ZeroMQ_Connector(_pulldata_handlers=[hnd], _subdata_handlers=[hnd])
```
