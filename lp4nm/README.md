Log Processor for Nginx error log monitoring
============================================
The script will tail the error log and read each line to catch the *404 not found error* message, and send to *nagios server* with [snmr](https://github.com/cloved/SimpleNagiosMessageReciever).
