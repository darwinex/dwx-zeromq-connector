# DWX_ZeroMQ MT5 support
Here I would like to propose my version of MT5 support for DWX_ZeroMQ witch consists of 3 different things.
## Using service instead od EA
Implementing DWX_ZeroMQ_Service I used completely new approach because, instead of typical EA I chose new type of mql5 application called **Service**. Unlike scripts, EAs and indicators this kind of program does not need any chart and works in the background of the MT5 terminal. If added, such application is launched automatically when the terminal starts and does not conflict with any other service or EAs. Like scripts service has only **OnStart** handler function. Please follow these steps to check it out:
1. Place file to **MQL5/Services** folder:

   ![Service folder location](images/services_location.png)
1. Refresh terminal and from context menu choose **Add service**. 

   ![Service add](images/services_add.png)
1. Configure service like standard EA: **Allow Automated Trading**, etc. 

   ![Service configure](images/services_configure.png)
1. Manage the service using **Start**, **Stop** or **Remove** from the terminal. 

   ![Service management](images/services_manage.png)
## Separating pending orders and working orders
MQL5 algorithmic trading is much more complicated than MQL4 one. In the same time it gives much more possibilities. So I thought it is a good idea to prepare new trading interface and separate pending orders and working positions. Also publishing new quotes data is much easier im MQL5. The service will not miss any new tick, even if there were more than one tick since last checking cycle: ![Service data publishing](images/tick_data_publishing_example.png) I think that looking for compatibility with MQL4 could be difficult while developing the projekt and should not be considered.
## Simplification of communication string
My last proposal is to simplify communication 'protocol' between server and client by replacing 'TRADE|DATA' and 'ACTION' with predefined enum type. This would allow to replace inefficient stack of string comparsions with one string to number conversion.
Implementation of the service is based on code from *DWX_ZeroMQ_Server_v2.0.1_RC8.mq4* file. I tried to stick to the original coding style and modify as less as possible. All newly implemented conceptions should be well commented in the code.
To not mess up I created new python temporary files:
* **DWX_ZeroMQ_Connector_v1_0.py**
* **DWX_ZMQ_Execution_MT5.py**
* **DWX_ZMQ_Reporting_MT5.py**
* **DWX_ZMQ_Strategy_MT5.py**
* **coin_flip_traders_v1.0_MT5.py**
