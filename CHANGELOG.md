# DWX ZeroMQ Connector  { Python 3 to MetaTrader 4 }

# Pull-request description for version: 2.0.1 [(here)](https://github.com/raulMrello/dwx-zeromq-connector)

## Table of Contents
* [Introduction](#introduction)
* [Prices feed](#prices-feed)
* [Historic of Rates](#historic-of-rates)
* [Rates feed](#rates-feed)
* [Notifications of new received data](#notifications-of-new-received-data)
* [List of changes](#list-of-changes)
* [Examples](#examples)
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

_Example 3: Also, clients can clears the symbol list managed by the EA, sending a request without symbols:_

```cpp
TRACK_PRICES
```

In order to provide this new functionality a new method is added to the ```ZMQ-Connector```:

```cpp
def _DWX_MTX_SEND_TRACKPRICES_REQUEST_(self,_symbols=['EURUSD'])
```

On the other hand, Expert Advisor is modified, to accept this new command request, provide an associated response and update the list of symbols managed by itself. The response to this request <```TRACK_PRICES;GDAXI;EURGBP```> is as follows:

```cpp
{
  '_action': 'TRACK_PRICES',
  '_data': {
    '_symbol_count': 2
  }
}
```

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

As previously, Expert Advisor is modified to process this new request properly. The response to this request <```TRACK_RATES;GDAXI;1```> is as follows:

```cpp
{
  '_action': 'TRACK_RATES',
  '_data': {
    '_instrument_count': 1
  }
}
```

When a client is subscribed to a rate feed, it will receive the response through the SUB port and the message will be in this format ```TOPIC MESSAGE``` where ```TOPIC``` is the instrument name and ```MESSAGE``` is the rate price.

```cpp
+-- TOPIC------+ +----------- Message -------------------------+
SYMBOL_TIMEFRAME TIME;OPEN;HIGH;LOW;CLOSE;TICKVOL;SPREAD;REALVOL
```

_Example:_

```cpp
EURUSD_H1  1556523690;1.15115;1.15155;1.15105;1.15125;30;0;0
```
_Note: field ```TIME``` is the unix timestamp in integer format (1556523690 = 2019/04/29 at 7:41am UTC)_


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

### **_Rate prices streaming_**

As said before, rates are also streamed through the SUB port when a client is subscribed to them. In this case, they are also streamed into ```_zmq._Market_Data_DB``` dictionary using the instrument's name.

So, for a rate stream from instrument ```EURUSD_H1```, data inserted into dict will be in this format:

```cpp
Output: 
{'EURUSD_H1': {
  '2019-01-08 10:00:49.157431': (1546952449;1.15115;1.15155;1.15105;1.15125;30;0;0),
  '2019-01-08 11:00:50.673151': (1546956050;1.15116;1.15146;1.15107;1.15122;50;5;0),
  '2019-01-08 12:00:51.010993': (1546959651;1.15114;1.15153;1.15106;1.15121;10;10;0),
  ...,

```

---
## Examples

In folder [v2.0.2/python/examples/template/strategies](https://github.com/raulMrello/dwx-zeromq-connector/tree/release/v2.0.2/v2.0.2/python/examples/template/strategies) I provide different examples, showing these new features:

- [prices_subscriptions.py](https://github.com/raulMrello/dwx-zeromq-connector/blob/release/v2.0.2/v2.0.2/python/examples/template/strategies/prices_subscriptions.py): in this example a Client modify symbol list configured in the EA to get bid-ask prices from EURUSD and GDAXI. When it receives 10 prices from each feed, it will cancel GDAXI feed and only receives 10 more prices from EURUSD. Once received those next 10 prices, it cancels all prices feeds and finishes.

```cpp
OUTPUT:
Loading example...
[INIT] Ready to send commands to METATRADER (PUSH): 32768
[INIT] Listening for responses from METATRADER (PULL): 32769
\Running example...
[KERNEL] Subscribed to EURUSD MARKET updates. See self._Market_Data_DB.
Subscribed to EURUSD price feed
[KERNEL] Subscribed to GDAXI MARKET updates. See self._Market_Data_DB.
Subscribed to GDAXI price feed
Configuring price feed for 2 symbols
Response from ExpertAdvisor={'_action': 'TRACK_PRICES', '_data': {'symbol_count': 2}}
Waiting example termination...
Data on Topic=EURUSD with Message=1.116400;1.116430
Data on Topic=GDAXI with Message=12311.300000;12312.000000
Data on Topic=EURUSD with Message=1.116400;1.116400
Data on Topic=GDAXI with Message=12310.300000;12311.000000
Data on Topic=EURUSD with Message=1.116370;1.116380
Data on Topic=GDAXI with Message=12309.800000;12310.500000
Data on Topic=EURUSD with Message=1.116360;1.116380
Data on Topic=GDAXI with Message=12309.800000;12310.500000
Data on Topic=EURUSD with Message=1.116370;1.116400
Data on Topic=GDAXI with Message=12309.800000;12310.500000
Data on Topic=EURUSD with Message=1.116360;1.116400
Data on Topic=GDAXI with Message=12309.800000;12310.500000
Data on Topic=EURUSD with Message=1.116370;1.116410
Data on Topic=GDAXI with Message=12309.800000;12310.500000
Data on Topic=EURUSD with Message=1.116380;1.116410
Data on Topic=GDAXI with Message=12309.800000;12310.500000
Data on Topic=EURUSD with Message=1.116370;1.116390
Data on Topic=GDAXI with Message=12309.300000;12310.000000
Data on Topic=EURUSD with Message=1.116360;1.116390
Data on Topic=GDAXI with Message=12309.300000;12310.000000
[KERNEL] Subscribed to EURUSD MARKET updates. See self._Market_Data_DB.
Subscribed to EURUSD price feed
Configuring price feed for 1 symbols
Response from ExpertAdvisor={'_action': 'TRACK_PRICES', '_data': {'symbol_count': 1}}
Data on Topic=EURUSD with Message=1.116370;1.116390
Data on Topic=EURUSD with Message=1.116390;1.116420
Data on Topic=EURUSD with Message=1.116380;1.116400
Data on Topic=EURUSD with Message=1.116380;1.116420
Data on Topic=EURUSD with Message=1.116390;1.116420
Data on Topic=EURUSD with Message=1.116350;1.116350
Data on Topic=EURUSD with Message=1.116310;1.116330
Data on Topic=EURUSD with Message=1.116320;1.116340
Data on Topic=EURUSD with Message=1.116320;1.116350
Data on Topic=EURUSD with Message=1.116310;1.116340
**
[KERNEL] Setting Status to False - Deactivating Threads.. please wait a bit.
**
Unsubscribing from all topics
Removing symbols list
Removing instruments list
Bye!!!
```


- [rates_subscriptions.py](https://github.com/raulMrello/dwx-zeromq-connector/blob/release/v2.0.2/v2.0.2/python/examples/template/strategies/rates_subscriptions.py): in this example a Client modify instrument list configured in the EA to get rate prices from EURUSD at M1 and GDAXI at M5. After receiving 5 rates from EURUSD_M1 it cancels its feed and waits 2 rates from GDAXI. At this point it cancels all rate feeds and waits for 2 minutes. Then it prints ```_zmq._Market_Data_DB``` dictionary and finishes.

```cpp
OUTPUT:
Loading example...
[INIT] Ready to send commands to METATRADER (PUSH): 32768
[INIT] Listening for responses from METATRADER (PULL): 32769
\Running example...
[KERNEL] Subscribed to EURUSD_M1 MARKET updates. See self._Market_Data_DB.
Subscribed to ('EURUSD_M1', 'EURUSD', 1) rate feed
[KERNEL] Subscribed to GDAXI_M5 MARKET updates. See self._Market_Data_DB.
Subscribed to ('GDAXI_M5', 'GDAXI', 5) rate feed
Configuring rate feed for 2 instruments
Response from ExpertAdvisor={'_action': 'TRACK_RATES', '_data': {'instrument_count': 2}}
Waiting example termination...
Data on Topic=EURUSD_M1 with Message=1556542800;1.116190;1.116190;1.116110;1.116140;45;0;0
Data on Topic=GDAXI_M5 with Message=1556542800;12289.400000;12289.900000;12285.900000;12289.400000;47;0;0
Data on Topic=EURUSD_M1 with Message=1556542860;1.116170;1.116170;1.116170;1.116170;1;0;0
Data on Topic=EURUSD_M1 with Message=1556542920;1.116150;1.116150;1.116150;1.116150;1;0;0
Data on Topic=EURUSD_M1 with Message=1556542980;1.116170;1.116170;1.116170;1.116170;1;0;0
Data on Topic=EURUSD_M1 with Message=1556543040;1.116170;1.116170;1.116170;1.116170;1;0;0
[KERNEL] Subscribed to GDAXI_M5 MARKET updates. See self._Market_Data_DB.
Subscribed to ('GDAXI_M5', 'GDAXI', 5) rate feed
Configuring rate feed for 1 instruments
Response from ExpertAdvisor={'_action': 'TRACK_RATES', '_data': {'instrument_count': 1}}
Data on Topic=GDAXI_M5 with Message=1556542800;12289.400000;12294.900000;12285.900000;12292.400000;117;0;0
Data on Topic=GDAXI_M5 with Message=1556543100;12293.400000;12293.400000;12291.900000;12291.900000;2;0;0
**
[KERNEL] Setting Status to False - Deactivating Threads.. please wait a bit.
**
Unsubscribing from all topics
Removing symbols list
Removing instruments list

self._Market_Data_DB = {
 'EURUSD_M1': {
  '2019-04-29 10:00:51.219693': (1556542800, 1.11619, 1.11619, 1.11611, 1.11614, 45, 0, 0), 
  '2019-04-29 10:01:01.597655': (1556542860, 1.11617, 1.11617, 1.11617, 1.11617, 1, 0, 0), 
  '2019-04-29 10:02:03.343480': (1556542920, 1.11615, 1.11615, 1.11615, 1.11615, 1, 0, 0), 
  '2019-04-29 10:03:03.720442': (1556542980, 1.11617, 1.11617, 1.11617, 1.11617, 1, 0, 0), 
  '2019-04-29 10:04:04.212392': (1556543040, 1.11617, 1.11617, 1.11617, 1.11617, 1, 0, 0)}, 
 'GDAXI_M5': {
   '2019-04-29 10:00:51.220693': (1556542800, 12289.4, 12289.9, 12285.9, 12289.4, 47, 0, 0), 
   '2019-04-29 10:04:05.019311': (1556542800, 12289.4, 12294.9, 12285.9, 12292.4, 117, 0, 0), 
   '2019-04-29 10:05:10.458767': (1556543100, 12293.4, 12293.4, 12291.9, 12291.9, 2, 0, 0)}
}

Bye!!!
```

- [rates_historic.py](https://github.com/raulMrello/dwx-zeromq-connector/blob/release/v2.0.2/v2.0.2/python/examples/template/strategies/rates_historic.py): in this example a Client request a rate historic from EURGBP Daily from the last 5 days. 

```cpp
OUTPUT:
Loading example...
[INIT] Ready to send commands to METATRADER (PUSH): 32768
[INIT] Listening for responses from METATRADER (PULL): 32769
\Running example...
Waiting example termination...
Historic from ExpertAdvisor={
  '_action': 'HIST', 
  '_data': [
    {'time': '2019.01.07 00:00', 'open': 1.13952, 'high': 1.14823, 'low': 1.13952, 'close': 1.14737, 'tick_volume': 88454, 'spread': 0, 'real_volume': 0}, 
    {'time': '2019.01.08 00:00', 'open': 1.14736, 'high': 1.14845, 'low': 1.14225, 'close': 1.14397, 'tick_volume': 89843, 'spread': 0, 'real_volume': 0}, 
    {'time': '2019.01.09 00:00', 'open': 1.14399, 'high': 1.15581, 'low': 1.14368, 'close': 1.15422, 'tick_volume': 117184, 'spread': 0, 'real_volume': 0}, 
    {'time': '2019.01.10 00:00', 'open': 1.15421, 'high': 1.15697, 'low': 1.14844, 'close': 1.14993, 'tick_volume': 110855, 'spread': 0, 'real_volume': 0}, 
    {'time': '2019.01.11 00:00', 'open': 1.1498, 'high': 1.15402, 'low': 1.14579, 'close': 1.14646, 'tick_volume': 96812, 'spread': 0, 'real_volume': 0}, 
    {'time': '2019.01.14 00:00', 'open': 1.14583, 'high': 1.14819, 'low': 1.14507, 'close': 1.1468, 'tick_volume': 88784, 'spread': 0, 'real_volume': 0}
  ]
}

**
[KERNEL] Setting Status to False - Deactivating Threads.. please wait a bit.
**
Unsubscribing from all topics
Removing symbols list
Removing instruments list
Bye!!!
```