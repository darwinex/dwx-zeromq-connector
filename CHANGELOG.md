# DWX ZeroMQ Connector  { Python 3 to MetaTrader 4 }

# Pull-request description for version: 2.0.1 [(here)](https://github.com/raulMrello/dwx-zeromq-connector)

## Table of Contents
* [Introduction](#introduction)
* [Prices feed](#price-feed)
* [Historic of Rates](#historic-rates)
* [Rates feed](#rates-feed)
* [Notifications of new received data](#notif-recv-data)
* [List of changes](#changelog)

---

## Introduction
Playing with this project during some time, I miss some important features both on the Client side (ZMQ-Connector) and on the Server side (Expert Advisor). 

With this pull request, some modifications have been added to both sides, to improve the capabilities provided by this project.

Along next sections, I'll explain them in more detail.

---
## Prices feed

In current version (v2.0.1), clients can subscribe to prices feeds (```bid,ask``` prices) from different symbols. Those symbols must be previouly configured in the Expert Advisor.

However, if clients (in runtime) do a new subscription to other symbols (not configured previously in the Expert Advisor), their prices feed never will be received, because those symbols are not configured yet in the EA.

The modification proposed here, implies a modification done in Expert Advisor code and ZMQ-Connector code, through which symbols can be configured in the Expert Advisor (runing on Server side) and hence, clients can change subscriptions to their prices feed during runtime.

---
## Historic of Rates

In current version, clients can request historic data from specific instruments (symbol & timeframe), and receive ```CLOSE``` prices for a period in time.

Nevertheless, there isn't a service to get ```RATE``` prices from those instruments, understanding a ```RATE``` as a data stream formed by these values: ```TIME,OPEN,HIGH,LOW,CLOSE,TICKVOL,SPREAD,REALVOL```.

This modification includes one new service providing this functionality.

---
## Rates feed

In current version, there is no way to get rates feed from specific instruments. 

The modification proposed here, allows that clients can modify instruments configured in the Expert Advisor and hence get subscribed to their rates feed during runtime.

---
## Notifications of new received data

In current version, data received from Server comes through PULL or SUB ports.

Data feeds comes through SUB port and are registered in the client's dictionary ```self._Market_Data_DB```. So, clients can check this dictionary periodically for new received data.

The proposed modification here, implies a change in ZMQ-Connector code. Now a data processor is registered in the Connector, acting as an event handler. Then, when new data is received through the PULL port, a callback is invoked ```dataHandler.onPullData(pull_port_data)```.

In the same way, data received through the SUB port is also notified through the callback ```dataHandler.onSubData(sub_port_data)```.

With the addition of these callbacks, now clients can execute in a more efficient way, via this event-driven framework.

---
## List of changes

Along this section I describe source code changes and new functionalities added.

### **_TRACK_PRICES command_**

This request is intended to change symbols configured in the Expert Advisor in runtime. So, the request is formed by the command and a list of symbols that must be managed by the Expert Advisor:

```cpp
TRACK_PRICES;SYMBOL_1;SYMBOL_2;SYMBOL_3;.....;SYMBOL_N
```

_Example 1: to start receiving bid-ask prices from EURUSD, GDAXI and EURGBP, clients can send this PUSH request to the Server side:_

```cpp
TRACK_PRICES;EURUSD;GDAXI;EURGBP
```

_Example 2: At any given time, clients can cancel EURUSD prices feed, updating that list with this new PUSH request:_

```cpp
TRACK_PRICES;GDAXI;EURGBP
```

_Example 3: Also, clients can clears the symbol list managed by the EA, sending a request without symbols:

```cpp
TRACK_PRICES
```

In order to provide this new functionality a new method is added to the ```ZMQ-Connector```:

```cpp
def _DWX_MTX_SEND_TRACKPRICES_REQUEST_(self,_symbols=['EURUSD'])
```

On the other hand, Expert Advisor is modified, to accept this new command request, provide an associated response and update the list of symbols managed by itself.

### **_TRACK_RATES command_**

This request is intended to change instruments configured in the Expert Advisor in runtime, so that clients could get subscribed to rate prices feeds. 

It is identified by the command: ```TRACK_RATES``` followed by a list of symbols and timeframes:

```cpp
TRACK_RATES;SYMBOL_1;TIMEFRAME_1;SYMBOL_2;TIMEFRAME_2;.....;SYMBOL_N;TIMEFRAME_N
```

_Example 1: to start receiving Rates(time-open-high-low-close-tickvol-spread-realvol) from EURUSD at timeframe M1, and from GDAXI at timeframe H4, clients can send this PUSH request to the Server side:_

```cpp
TRACK_RATES;EURUSD;1;GDAXI;240
```

_Note: H4 = 4hours = 4*60mins = 240mins (timeframe = 240)_

_Example 2: instrument list can be changed at any given time. Also can be cleared by a command without symbols-timeframes:_

```cpp
TRACK_RATES
```

In order to provide this new functionality a new method is added to the ```ZMQ-Connector```:

```cpp
def _DWX_MTX_SEND_TRACKRATES_REQUEST_(self,_instruments=[('EURUSD_M1','EURUSD',1)]):
```  

_Note: Instruments are tuples of 3 parameters (name, symbol, timeframe). In this case, name is formed with this format: ```SYMBOL_TIMEFRAME```, where ```TIMEFRAME``` holds values associated with standard timeframes: ```M1,M5,M15,M30,H1,H4,D1,W1,MN1```_

As previously, Expert Advisor is modified to process this new request properly.


### **_HIST command_**

This request is intended to request a historic of rates from an specific instrument. Similar to ```DATA``` request, its format is as follows:

```cpp
HIST;SYMBOL;TIMEFRAME;START_TIME;END_TIME
```

This functionality is added to the ```ZMQ-Connector``` by this new method:

```cpp
def _DWX_MTX_SEND_MARKETHIST_REQUEST_(self,
                                 _symbol='EURUSD',
                                 _timeframe=1,
                                 _start='2019.01.04 17:00:00',
                                 _end=Timestamp.now().strftime('%Y.%m.%d %H:%M:00')):
```

Also, Expert Advisor is modified to provide the requested historic data.

### **_Received data handlers_**

In this case, ```ZMQ-Connector``` is modified to accept the registration of two event handlers, that will be invoked when new data is received through the PULL or the SUB ports.

Now, the constructor of this class is modified as follows:

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


- ```_pulldata_handlers```: is a list of handlers that will be notified when new data arrives through the PULL port, calling to the public method ```handler.onPullData(new_data)```.

- ```_subdata_handlers```: is a list of handlers that will be notified when new data arrives through the SUB port, calling to the public method ```handler.onSubData(new_data)```.

A common implementation of a handler that can get notifications from both sockets could be this one:

```cpp
class Handler():
    """ Handles PULL socket data """
    def onPullData(self, new_data):
        print('Received new data on PULL socket ={}'.format(new_data))

    """ Handles SUB socket data """
    def onSubData(self, new_data):
        print('Received new data on SUB socket ={}'.format(new_data))   
```

And then a Client, could start ZMQ connector installing these handlers, in this way:


```cpp
hnd = Handler()
zmq = DWX_ZeroMQ_Connector(_pulldata_handlers=[hnd], _subdata_handlers=[hnd])
```
