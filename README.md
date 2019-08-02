## Description
A Linux script to easily install and enable the bias tee from an **RTL-SDR Blog V3** USB dongle to power the **RTL-SDR Blog ADS-B Triple Filtered LNA**.


## Install & Enable Bias Tee
Run the following command to install and enable the bias tee.  Be sure the RTL-SDR Blog V3 USB dongle and the RTL-SDR Blog ADS-B Triple Filtered LNA are both connected before running this script!
```
bash -c "$(wget -O - https://github.com/mypiaware/rtlsdr_bias_tee/raw/master/rtlsdr_bias_tee.sh)"
```


## Cron Job
It is suggested to make a cron job to run the 'daemon-reload' command at system boot. Running this cron job is not necessary at all, and the bias tee will still be enabled with or without this cron job.  However, this cron job may prevent the `Run 'systemctl daemon-reload'` message every time dump1090 is restarted.  How to create the cron job:

1.  Run: `sudo crontab -e`
2.  If this is the first time running crontab for root, then choose the preferred text editor.
3.  Type this for the cron job:  `@reboot systemctl daemon-reload`


## Compatibility:
This bias tee installation script has been tested and confirmed to work with the following:
* FlightAware's PiAware SD image (3.7.1)
* **_dump1090-fa_** addon package installed on Raspbian Stretch and Buster
* **_dump1090-mutability_** addon package installed on Raspbian Stretch and Buster
