#!/bin/bash


# Purpose of this script:  To help activate the bias tee from an "RTL-SDR Blog V3" USB dongle to power the "RTL-SDR Blog ADS-B Triple Filtered LNA".
#
# Main sources of help for creating this script:
#    https://www.rtl-sdr.com/getting-the-v3-bias-tee-to-activate-on-piaware-ads-b-images/
#    https://osmocom.org/projects/rtl-sdr/wiki/Rtl-sdr
#    https://discussions.flightaware.com/t/dump1090-mutability-v1-15-dev-and-rtl-sdr-v3-bias-t-auto-switch-on/34693
#    https://discussions.flightaware.com/t/rtl-v3-bias-t-cant-enable/52831/3
#
# This script will not run unless 'dump1090-fa' or 'dump1090-mutability' is installed.
# Confirmed to run on Raspbian Stretch-Lite & Raspbian Buster-Lite & PiAware SD Image (3.7.1).
# Nearly every command is checked for a successful execution to help isolate any possible failures.
# Script credit:  https://github.com/mypiaware



##############################  Global variables.  ##############################



# A few global variables (may be changed if needed or desired).
HOMEUSER="$(id -u -n)"                 # The username of the user running this script. Typically, on Raspbian, this will simply be: "pi".
RTLDIR="/home/$HOMEUSER/.biastee"      # An arbitrary directory where to download/clone the Git repository.
BIASTCONFIGFILENAME_FA="biastee.conf"  # Filename of file used to allow bias tee to start before dump1090-fa at every system boot.
DEVNUM=0                               # It is assumed only one USB dongle is being used.  Otherwise, it may be necessary to change the device number here.

# Other global variables that should not be changed or are simply declared.
declare DUMPVERSION                 # Global variable to hold the dump1090 version.
declare BIAST_DOWNLOADED            # Global variable to hold a binary value of whether or not the bias tee software has been downloaded.
declare BIAST_INSTALLED             # Global variable to hold a binary value of whether or not the bias tee software has been installed.
BUILDDIR="$RTLDIR/build"            # Directory where bias tee software will be built.
BIASTCMD="$BUILDDIR/src/rtl_biast"  # The bias tee command string.
FA_SERVICE_DIR="/etc/systemd/system/dump1090-fa.service.d"    # Global variable just to shorten the full path of dump1090-fa's service directory.
BIASTCONFIGFILE_FA="$FA_SERVICE_DIR/$BIASTCONFIGFILENAME_FA"  # Global variable just to shorten the full path for this config file.



##############################  A few minor functions this script will use.  ##############################



function REDTEXT {  # Use this function to easily create a color to text in the command line environment.
   local RED_COLOR='\033[1;31m'
   local NO_COLOR='\033[0m'
   printf "${RED_COLOR}%s${NO_COLOR}" "$1"
}

function GREENTEXT {  # Use this function to easily create a color to text in the command line environment.
   local GREEN_COLOR='\033[1;32m'
   local NO_COLOR='\033[0m'
   printf "${GREEN_COLOR}%s${NO_COLOR}" "$1"
}

function BLUETEXT {  # Use this function to easily create a color to text in the command line environment.
   local BLUE_COLOR='\033[1;34m'
   local NO_COLOR='\033[0m'
   printf "${BLUE_COLOR}%s${NO_COLOR}" "$1"
}

function ORANGETEXT {  # Use this function to easily create a color to text in the command line environment.
   local ORANGE_COLOR='\033[0;33m'
   local NO_COLOR='\033[0m'
   printf "${ORANGE_COLOR}%s${NO_COLOR}" "$1"
}

function PURPLETEXT {  # Use this function to easily create a color to text in the command line environment.
   local PURPLE_COLOR='\033[0;35m'
   local NO_COLOR='\033[0m'
   printf "${PURPLE_COLOR}%s${NO_COLOR}" "$1"
}

function ERROREXIT {  # Run this function after a command to report a failure with the command if any exists and report a supplied error code.
   if [ $? -ne 0 ]; then
      REDTEXT "ERROR! $2"
      printf "\n"
      REDTEXT "Error Code: $1"
      printf "\n"
      exit $1
   fi
}

function PAUSESCRIPT { read -p ""; }



##############################  A few of the initial functions this script will use.  ##############################



function CHECKSUDO {  # Do not run this script as root because not every directory/file created needs to be owned by root.
   if [[ $EUID == 0 ]]; then
      printf "\n"
      REDTEXT "An ERROR occurred! The script can not continue!"
      printf "\n"
      printf "Do NOT run this script as root! (Do not use 'sudo' in the command.)\n\n"
      exit 1
   fi
   # Script is not to be run with sudo privilege.
   # However sudo rights will be necessary for some commands.  Therefore, go ahead and get sudo privilege now. (May not be needed for Raspbian.)
   sudo ls >/dev/null 2>&1  # Dummy command just to get a prompt for the user's password for the sake of using sudo.
}

function WHICHDUMP {  # Determine which flavor of dump1090 is installed, if any.
   local FOUND_FA=0
   local FOUND_MUTABILITY=0
   if which dump1090-fa >/dev/null 2>&1;         then FOUND_FA=1;         fi
   if which dump1090-mutability >/dev/null 2>&1; then FOUND_MUTABILITY=1; fi
   if   [ $FOUND_FA -eq 1 ] && [ $FOUND_MUTABILITY -eq 0 ]; then DUMPVERSION="dump1090-fa"          # Global variable
   elif [ $FOUND_FA -eq 0 ] && [ $FOUND_MUTABILITY -eq 1 ]; then DUMPVERSION="dump1090-mutability"  # Global variable
   elif [ $FOUND_FA -eq 0 ] && [ $FOUND_MUTABILITY -eq 0 ]; then
      printf "\n"
      REDTEXT "An ERROR occurred! This script can not continue!"
      printf "\n"
      printf "It appears neither 'dump1090-fa' nor 'dump1090-mutability' is installed!\n"
      printf "Install either 'dump1090-fa' or 'dump1090-mutability', then run this script.\n\n"
      exit 2
   elif [ $FOUND_FA -eq 1 ] && [ $FOUND_MUTABILITY -eq 1 ]; then
      printf "\n"
      REDTEXT "An ERROR occurred! This script can not continue!"
      printf "\n"
      printf "It appears both 'dump1090-fa' and 'dump1090-mutability' are installed!\n"
      printf "Only one version of dump1090 should be installed before running this script.\n\n"
      exit 3
   else ERROREXIT 93 "Unknown error occurred!"
   fi
}

function CHECK_SOFTWARE_STATUS {  # Check if bias tee is installed, or even if it is in a rare situation of being downloaded but not installed.
   $BIASTCMD -? >/dev/null 2>&1
   if [[ $? -eq 1 ]]; then
      BIAST_INSTALLED=1   # Global variable
      BIAST_DOWNLOADED=1  # Global variable
   else
      BIAST_INSTALLED=0  # Global variable
      if [[ -d $RTLDIR ]] && [ "$(ls -A $RTLDIR)" ]; then
         BIAST_DOWNLOADED=1  # Global variable
      else
         BIAST_DOWNLOADED=0  # Global variable
      fi
   fi
}

function BACKUPDUMPMUTABILITY {  # Always safe to make sure a copy of 'dump1090-mutability' is made prior to any edits to this file if dump1090-mutability is used.
   if [ -f /etc/init.d/dump1090-mutability ]; then
      if ! [ -f /etc/init.d/dump1090-mutability.original ]; then
         sudo cp /etc/init.d/dump1090-mutability /etc/init.d/dump1090-mutability.original;  ERROREXIT 10 "Failed to copy the 'dump1090-mutability' file!"
      fi
   fi
}

function WELCOME {
   printf "\n\n\n"
   BLUETEXT " Welcome!"; printf "\n\n"
   BLUETEXT " This script will install/uninstall & activate/deactivate the"; printf "\n"
   BLUETEXT " RTL-SDR Blog V3 bias tee to power the RTL-SDR Blog ADS-B Triple Filtered LNA."; printf "\n\n"
   BLUETEXT " Version of dump1090 detected:  ";  printf "$DUMPVERSION\n\n"
   REDTEXT  " Be sure the RTL-SDR USB dongle and LNA are both connected before continuing!"
   printf "\n"
}



##############################  Functions to either clone/build the bias tee software or to completely uninstall/remove it.  ##############################



function INSTALL {  # Download and install the bias tee software.
   sudo apt-get update;                                                            ERROREXIT 11 "The 'apt-get update' command failed!"
   sudo apt-get install -y git cmake build-essential libusb-1.0;                   ERROREXIT 12 "Failed to download/install dependencies!"
   rm -rf $RTLDIR;                                                                 ERROREXIT 13 "Failed to delete the '$RTLDIR' directory!"
   mkdir -p $RTLDIR;                                                               ERROREXIT 14 "Failed to create the '$RTLDIR' directory!"  # Make sure $RTLDIR is empty.
   git clone https://github.com/rtlsdrblog/rtl_biast $RTLDIR;                      ERROREXIT 15 "Failed to download/clone Git repository!"
   mkdir -p $BUILDDIR;                                                             ERROREXIT 16 "Failed to create the '$BUILDDIR' directory!"
   cmake -B$BUILDDIR -H$RTLDIR -DINSTALL_UDEV_RULES=ON -DDETACH_KERNEL_DRIVER=ON;  ERROREXIT 17 "The 'cmake' command failed!"
   make -C $BUILDDIR;                                                              ERROREXIT 18 "The 'make' command failed!"
   sudo make install -C $BUILDDIR;                                                 ERROREXIT 19 "The 'make install' command failed!"
   sudo ldconfig;                                                                  ERROREXIT 20 "The 'ldconfig' command failed!"
}

function UNINSTALL {  # Try to restore everything to the way it was before bias tee was installed.
   if [[ $DUMPVERSION = "dump1090-fa" ]]; then
      if [ -f $BIASTCONFIGFILE_FA ]; then sudo rm $BIASTCONFIGFILE_FA;  fi;                                   ERROREXIT 21 "Failed to delete the '$BIASTCONFIGFILE_FA' file!"
   elif [[ $DUMPVERSION = "dump1090-mutability" ]]; then
      sudo perl -0 -i -pe "s|\s*$BIASTCMD\s+-d\s+[0-9]+\s+-b\s+[01]\n+|\n|" /etc/init.d/dump1090-mutability;  ERROREXIT 22 "Failed to edit the 'dump1090-mutability' file!"
   else
      ERROREXIT 94 "Unknown error occurred!"
   fi
   sudo systemctl daemon-reload;         ERROREXIT 23 "The 'daemon-reload' command failed!"
   sudo systemctl stop $DUMPVERSION;     ERROREXIT 24 "Failed to stop '$DUMPVERSION'!"
   $BIASTCMD -d $DEVNUM -b 0             # Does not produce a reliable exit/error code.
   sudo systemctl restart $DUMPVERSION;  ERROREXIT 25 "Failed to start '$DUMPVERSION'!"
   sudo make uninstall -C $BUILDDIR;     ERROREXIT 26 "The 'make uninstall' command failed!"
   sudo make clean -C $BUILDDIR;         ERROREXIT 27 "The 'make clean' command failed!"
   rm -rf $RTLDIR;                       ERROREXIT 28 "Failed to delete the '$RTLDIR' directory!"
}



##############################  Functions to temporarily enable/disable bias tee on either dump1090-fa or dump1090-mutability.  ##############################



function TEMP_ENABLE_DISABLE_FA {  # Temporarily enable/disable bias tee on dump1090-fa.
   local ONOFF=$1  # 1=enable. 0=disable.
   local TEMPFILE="/tmp/biastconfigfiletemp"
   if [[ $ONOFF -eq 1 ]]; then printf "Temporarily enabling the bias tee now....."; fi
   if [[ $ONOFF -eq 0 ]]; then printf "Temporarily disabling the bias tee now....."; fi
   if [ -f $BIASTCONFIGFILE_FA ]; then
      sudo mv $BIASTCONFIGFILE_FA $TEMPFILE >/dev/null 2>&1;  ERROREXIT 29 "Failed to move the '$BIASTCONFIGFILE_FA' file!"
      sudo systemctl daemon-reload;                           ERROREXIT 30 "The 'daemon-reload' command failed!"
   fi
   sudo systemctl stop $DUMPVERSION;                          ERROREXIT 31 "Failed to stop '$DUMPVERSION'!"
   printf "\n\n"
   $BIASTCMD -d $DEVNUM -b $ONOFF                             # Does not produce a reliable exit/error code.
   sudo systemctl restart $DUMPVERSION;                       ERROREXIT 32 "Failed to start '$DUMPVERSION'!"
   if [ -f $TEMPFILE ]; then
      sudo mv $TEMPFILE $BIASTCONFIGFILE_FA >/dev/null 2>&1;  ERROREXIT 33 "Failed to move the '$TEMPFILE' file!"
      sudo systemctl daemon-reload;                           ERROREXIT 34 "The 'daemon-reload' command failed!"
   fi
}

function TEMP_ENABLE_DISABLE_MUTABILITY {  # Temporarily enable/disable bias tee on dump1090-mutability.
   local ONOFF=$1  # 1=enable. 0=disable.
   if [[ $ONOFF -eq 1 ]]; then printf "Temporarily enabling the bias tee now....."; fi
   if [[ $ONOFF -eq 0 ]]; then printf "Temporarily disabling the bias tee now....."; fi
   sudo sed -i -r "s|($BIASTCMD\s+-d\s+[0-9]+\s+-b\s+[01])|#\1|" /etc/init.d/dump1090-mutability; ERROREXIT 35 "Failed to edit the 'dump1090-mutability' file!"
   sudo systemctl daemon-reload;                                                                  ERROREXIT 36 "The 'daemon-reload' command failed!"
   sudo systemctl stop $DUMPVERSION;                                                              ERROREXIT 37 "Failed to stop '$DUMPVERSION'!"
   printf "\n\n"
   $BIASTCMD -d $DEVNUM -b $ONOFF                                                                 # Does not produce a reliable exit/error code.   ### 'No supported devices found.'
   sudo systemctl restart $DUMPVERSION;                                                           ERROREXIT 38 "Failed to start '$DUMPVERSION'!"
   sudo sed -i -r "s|#($BIASTCMD\s+-d\s+[0-9]+\s+-b\s+[01])|\1|" /etc/init.d/dump1090-mutability; ERROREXIT 39 "Failed to edit the 'dump1090-mutability' file!"
   sudo systemctl daemon-reload;                                                                  ERROREXIT 40 "The 'daemon-reload' command failed!"
}



##############################  Functions to enable/disable bias tee at every system boot on either dump1090-fa or dump1090-mutability.  ##############################



function AUTO_ENABLE_DISABLE_FA {  # If enabling at every system boot, make sure bias tee starts up before dump1090-fa starts up at every system boot.
   local ONOFF=$1  # 1=enable. 0=disable.
   if [ -f $BIASTCONFIGFILE_FA ] && grep -qE "\[Service\]" $BIASTCONFIGFILE_FA && grep -qE "ExecStartPre\s*=\s*$BIASTCMD\s+-d\s+[0-9]+\s+-b\s+[1]" $BIASTCONFIGFILE_FA; then
      local BIASTENABLED=1; else local BIASTENABLED=0
   fi
   if [[ $ONOFF -eq 1 ]] && [[ $BIASTENABLED -eq 1 ]]; then
      printf "The bias tee is already enabled at every system boot."
   elif [[ $ONOFF -eq 1 ]] && [[ $BIASTENABLED -eq 0 ]]; then
      printf "Enabling the bias tee at every system boot....."
      sudo mkdir -p $FA_SERVICE_DIR;                                                                         ERROREXIT 41 "Failed to make the 'dump1090-fa.service.d' directory!"
      sudo touch $BIASTCONFIGFILE_FA;                                                                        ERROREXIT 42 "Failed to create the '$BIASTCONFIGFILENAME_FA' file!"
      echo "[Service]" | sudo tee $BIASTCONFIGFILE_FA >/dev/null 2>&1;                                       ERROREXIT 43 "Failed to edit the '$BIASTCONFIGFILENAME_FA' file!"
      echo "ExecStartPre=$BIASTCMD -d $DEVNUM -b $ONOFF" | sudo tee -a $BIASTCONFIGFILE_FA >/dev/null 2>&1;  ERROREXIT 44 "Failed to edit the '$BIASTCONFIGFILENAME_FA' file!"
      sudo systemctl daemon-reload;                                                                          ERROREXIT 45 "The 'daemon-reload' command failed!"
   elif [[ $ONOFF -eq 0 ]] && [[ $BIASTENABLED -eq 1 ]]; then
      printf "Disabling the bias tee at every system boot....."
      if [ -f $BIASTCONFIGFILE_FA ]; then
         sudo rm $BIASTCONFIGFILE_FA;       ERROREXIT 46 "Failed to delete the '$BIASTCONFIGFILENAME_FA' file!"
         sudo systemctl daemon-reload;      ERROREXIT 47 "The 'daemon-reload' command failed!"
      fi
   elif [[ $ONOFF -eq 0 ]] && [[ $BIASTENABLED -eq 0 ]]; then
      printf "The bias tee is already disabled at every system boot."
   else ERROREXIT 95 "Unknown error occurred!"
   fi
}

function AUTO_ENABLE_DISABLE_MUTABILITY {  # If enabling at every system boot, make sure bias tee starts up before dump1090-mutability starts up at every system boot.
   local ONOFF=$1  # 1=enable. 0=disable.
   if [[ $ONOFF -eq 1 ]]; then
      if ! grep -qE "$BIASTCMD\s+-d\s+[0-9]+\s+-b\s+[1]" /etc/init.d/dump1090-mutability; then
         printf "Enabling the bias tee at every system boot....."
         sudo perl -0 -i -pe "s|do_start\(\)\n+\{|do_start()\n{\n\t$BIASTCMD -d $DEVNUM -b $ONOFF\n|" /etc/init.d/dump1090-mutability;  ERROREXIT 48 "Failed to edit the 'dump1090-mutability' file!"
         sudo systemctl daemon-reload;                                                                                                  ERROREXIT 49 "The 'daemon-reload' command failed!"
      else
         printf "The bias tee is already enabled at every system boot."
      fi
   elif [[ $ONOFF -eq 0 ]]; then
      if grep -qE "$BIASTCMD\s+-d\s+[0-9]+\s+-b\s+[01]" /etc/init.d/dump1090-mutability; then
         printf "Disabling the bias tee at every system boot....."
         sudo perl -0 -i -pe "s|\s*$BIASTCMD\s+-d\s+[0-9]+\s+-b\s+[01]\n+|\n|" /etc/init.d/dump1090-mutability;  ERROREXIT 50 "Failed to edit the 'dump1090-mutability' file!"
         sudo systemctl daemon-reload;                                                                           ERROREXIT 51 "The 'daemon-reload' command failed!"
      else
         printf "The bias tee is already disabled at every system boot."
      fi

   else ERROREXIT 96 "Unknown error occurred!"
   fi
}



##############################  Main functions prompting the user on what should be done.  ##############################



function DOWNLOAD_INSTALL_OPTION {  # First prompt to the user to ask on what to do (download/install,  uninstall/redownload/install, uninstall)
   local INSTALL_CHOICE
   if [[ $BIAST_INSTALLED -eq 0 ]] && [[ $BIAST_DOWNLOADED -eq 0 ]]; then
      GREENTEXT "Choose what to do:"; printf "\n"
      printf "1. Download & install the bias tee software.\n"
      printf "2. EXIT\n"
      while ! [[ $INSTALL_CHOICE =~ ^\s*[12]\s*$ ]]; do printf "Choice [1,2]: "; read INSTALL_CHOICE; done
      if [[ $INSTALL_CHOICE =~ [1] ]]; then
         INSTALL
      elif [[ $INSTALL_CHOICE =~ [2] ]]; then
         exit 0
      fi
   elif [[ $BIAST_INSTALLED -eq 0 ]] && [[ $BIAST_DOWNLOADED -eq 1 ]]; then
      PURPLETEXT "It appears that the bias tee software has been downloaded but not installed."; printf "\n\n"
      GREENTEXT "Choose what to do:"; printf "\n"
      printf "1. Re-download & install the bias tee software.\n"
      printf "2. EXIT\n"
      while ! [[ $INSTALL_CHOICE =~ ^\s*[12]\s*$ ]]; do printf "Choice [1,2]: "; read INSTALL_CHOICE; done
      if [[ $INSTALL_CHOICE =~ [1] ]]; then
         UNINSTALL
         INSTALL
      elif [[ $INSTALL_CHOICE =~ [2] ]]; then
         exit 0
      fi
   elif [[ $BIAST_INSTALLED -eq 1 ]] && [[ $BIAST_DOWNLOADED -eq 1 ]]; then
      PURPLETEXT "It appears that the bias tee software has already been downloaded & installed."; printf "\n\n"
      GREENTEXT "Choose what to do:"; printf "\n"
      printf "1. Uninstall, re-download & re-install the bias tee software.\n"
      printf "2. Uninstall the bias tee software.\n"
      printf "3. View bias tee enable/disable options.\n"
      printf "4. EXIT\n"
      while ! [[ $INSTALL_CHOICE =~ ^\s*[1-4]\s*$ ]]; do printf "Choice [1-4]: "; read INSTALL_CHOICE; done
      if [[ $INSTALL_CHOICE =~ [1] ]]; then
         printf "\n"; PURPLETEXT "Biast tee uninstalling & re-installing..."; printf "\n"
         UNINSTALL
         INSTALL
         printf "\n"; PURPLETEXT "Biast tee re-installed."; printf "\n"
      elif [[ $INSTALL_CHOICE =~ [2] ]]; then
         printf "\n"; PURPLETEXT "Biast tee uninstalling..."; printf "\n"
         UNINSTALL
         printf "\n"; PURPLETEXT "Biast tee uninstalled."; printf "\n"
         exit 0
      elif [[ $INSTALL_CHOICE =~ [4] ]]; then
         exit 0
      fi
   else ERROREXIT 97 "Unknown error occurred!"
   fi
}

function TEMP_ENABLE_DISABLE_OPTION {  # Second prompt to the user asking if bias tee should be temporarily enabled or disabled.
   local ENABLE_DISABLE_CHOICE
   GREENTEXT "Temporarily enable or disable the bias tee now?"; printf "\n"
   printf "1. Temporarily enable now\n"
   printf "2. Temporarily disable now\n"
   printf "3. EXIT\n"
   while ! [[ $ENABLE_DISABLE_CHOICE =~ ^\s*[1-3]\s*$ ]]; do printf "Choice [1-3]: "; read ENABLE_DISABLE_CHOICE; done
   if [[ $ENABLE_DISABLE_CHOICE =~ [12] ]]; then
      printf "\n"
      if   [[ $DUMPVERSION = "dump1090-fa" ]];         then TEMP_ENABLE_DISABLE_FA $((2-$ENABLE_DISABLE_CHOICE))          # User selects 1 for enable & 2 for disable.  Value sent will therefore be 1 for enable & 0 for disable.
      elif [[ $DUMPVERSION = "dump1090-mutability" ]]; then TEMP_ENABLE_DISABLE_MUTABILITY $((2-$ENABLE_DISABLE_CHOICE))  # User selects 1 for enable & 2 for disable.  Value sent will therefore be 1 for enable & 0 for disable.
      else ERROREXIT 98 "Unknown error occurred!"
      fi
   elif [[ $ENABLE_DISABLE_CHOICE =~ [3] ]]; then
      exit 0
   fi
}

function AUTO_ENABLE_DISABLE_OPTION {  # Third prompt to the user asking if bias tee should be enabled or disabled at every system boot.
   local ENABLE_DISABLE_CHOICE
   GREENTEXT "Enable or disable the bias tee at every system boot?"; printf "\n"
   printf "1. Enable at boot\n"
   printf "2. Disable at boot\n"
   printf "3. EXIT\n"
   while ! [[ $ENABLE_DISABLE_CHOICE =~ ^\s*[123]\s*$ ]]; do printf "Choice [1-3]: "; read ENABLE_DISABLE_CHOICE; done
   if [[ $ENABLE_DISABLE_CHOICE =~ [12] ]]; then
      printf "\n"
      if   [[ $DUMPVERSION = "dump1090-fa" ]];         then AUTO_ENABLE_DISABLE_FA $((2-$ENABLE_DISABLE_CHOICE))          # Send a '0' for disable.  Send a '1' for enable.
      elif [[ $DUMPVERSION = "dump1090-mutability" ]]; then AUTO_ENABLE_DISABLE_MUTABILITY $((2-$ENABLE_DISABLE_CHOICE))  # Send a '0' for disable.  Send a '1' for enable.
      else ERROREXIT 99 "Unknown error occurred!"
      fi
      printf "\n"
   elif [[ $ENABLE_DISABLE_CHOICE =~ [3] ]]; then
      exit 0
   fi
}



##############################  Main script below.  ##############################



CHECKSUDO              # Check if this script is ran as root. (It should not be ran as root.)
WHICHDUMP              # Check which version of dump1090 ('-fa' or '-mutability') is installed.  Exit if neither or both are installed.
CHECK_SOFTWARE_STATUS  # Check if bias tee has already been downloaded/installed.
BACKUPDUMPMUTABILITY   # If running dump1090-mutability, then make a copy of its configuration file.
WELCOME                # Display a quick welcome message.
printf "\n"
GREENTEXT "Press [ENTER] to continue..."
PAUSESCRIPT
printf "\n"
DOWNLOAD_INSTALL_OPTION     # Based on the status of the bias tee software (downloaded and/or installed), prompt user on how to start this script.
printf "\n"
TEMP_ENABLE_DISABLE_OPTION  # Offer an option to manually temporarily activate or deactivate the bias tee now.
printf "\n"
AUTO_ENABLE_DISABLE_OPTION  # Offer an option to activate or deactivate the bias tee at every system boot.
printf "\n"
BLUETEXT "Finished!"
printf "\n\n"
sync
exit 0
