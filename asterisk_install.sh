#!/bin/bash
# Gregory Conroy CTS4348 U03 Term Project
# Version: 1.0
# TODO: Prompt for sample use; generate slim config files through extensive prompting; validation/error catching.
# 
# This script was designed to run on a minimal CentOS install and must be run as root.

# Default Install Paths
ASTERISK_PATH="/etc/asterisk"
PJSIP_PATH="$ASTERISK_PATH/pjsip.conf"
PJSIP_CUSTOM_PATH="$ASTERISK_PATH/pjsip-custom.conf"
SIP_PATH="$ASTERISK_PATH/sip.conf"
SIP_CUSTOM_PATH="$ASTERISK_PATH/sip-custom.conf"
AEL_PATH="$ASTERISK_PATH/extensions.ael"
AEL_CUSTOM_PATH="$ASTERISK_PATH/extensions-custom.ael"

##################
# Base Functions #
##################

function logError {
    output "INSTALLER -- Error: $2" 1>&2
    exit $1
}
function input {
    output "INSTALLER -- Please enter a value for: $1"
    read $1
}
function output {
    echo "INSTALLER -- $1"
}

####################
# Helper Functions #
####################

function checkRoot {
    if [ "$(id -u)" != "0" ]
    then
       logError 1 "This script must be run as root."
    fi
}
function installAsterisk {
    output "Installing Asterisk core..."
    prepInstall
    yum install asterisk --enablerepo=asterisk-13 -y
    output "Done installing Asterisk packages."
    installAsteriskConfigs
}
function installAsteriskConfigs {
    output "Installing official Asterisk config samples..."
    yum install asterisk-configs -y
    output "Done installing config samples via package."
}
function loadConfig {
    output "Reading config..."
    # thanks to http://wiki.bash-hackers.org/howto/conffile
    if [ -z "$CONFIG_LOCATION" ]
    then
        source ./asterisk_install.cfg
    else
        source $CONFIG_LOCATION
    fi
    if [ -z "$EXTENSIONS" ] || [ -z "$PATTERNS" ] || [ -z "$STACK" ] || [ -z "$SPYING" ]
    then
        output "Config file not found or incomplete."
    else
        CONFIG=true
        output "Done reading config."
    fi
}
function prepInstall {
    output "Installing dependencies and repos..."
    yum install dnsmasq epel-release -y && yum install pwgen --enablerepo=epel -y && yum remove epel-release -y && yum update --enablerepo=asterisk-13 -y
    rpm -Uvh http://packages.asterisk.org/centos/6/current/i386/RPMS/asterisknow-version-3.0.1-3_centos6.noarch.rpm
    output "Done installing dependencies and repos; updated all system packages."
}
function restartAsterisk {
    output "Restarting Asterisk to commit changes and start fresh..."
    chown -R asterisk:asterisk /etc/asterisk
    /etc/init.d/asterisk restart
    output "Done restarting Asterisk."
}
function showHelp {
    echo "To use this script, include any of the following flags:"
    echo "-i,   install asterisk interactively"
    echo "-s,   silent install, to be used with -f"
    echo "-f,   specify location of config file"
    echo "-h,   show this prompt"
}
function walkthroughInstall {
    if [ -z "$CONFIG" ]
    then
        output "We'll now ask you some simple questions about your sample Asterisk config."
        output "What stack do you prefer, SIP or PJSIP? We recommend PJSIP."
        input "STACK"
        output "What extension patterns do you desire? Enter them semi-colon delimited and with Xs where the number may vary (ex. 1XXX or 1XX or 1X;2X)."
        input "PATTERNS"
        output "Now, how many extensions per pattern shall we create?"
        input "EXTENSIONS"
        output "Do you want to allow extensions to spy on one another? (Y/N)"
        input "SPYING"
    fi
}

#######
# AEL #
#######

function AELOutbound {
    output "Generating Outbound Context"
    if [[ "$SPYING" == Y* ]]
    then
        echo "context outbound {
            _XXXX => {
                Dial($STACK/\${EXTEN:-4});
                Hangup();
            }
        }" >> "$AEL_CUSTOM_PATH"
    else
        echo "context outbound {
            includes {
                spy;
            }
            _XXXX => {
                Dial($STACK/\${EXTEN:-4});
                Hangup();
            }
        }" >> "$AEL_CUSTOM_PATH"
    fi
}
function AELSpy {
    output "Generating Spy Context"
    echo "context spy {
        _*XXXX => {
            ChanSpy($STACK/\${EXTEN:-4},EsSd);
            Hangup();
        }
    }" >> "$AEL_CUSTOM_PATH"
}

#######
# SIP #
#######

function SIPPeerTemplate {
    output "Generating Peer Template $1"
    EXTENBLOCK=$(sed 's/X/0/g' <<< $1) # replace X with 0
    echo -e "[$EXTENBLOCK](!)\ntype=friend\nsecret=`pwgen -1`\nhost=dynamic\ndtmfmode=rfc2833\ncontext=outbound\ndirectmedia=no\nqualify=yes" >> "$SIP_CUSTOM_PATH"
}
function SIPPeer {
    output "Generating Peer $1 $2 $3"
    EXTENBLOCK=$(sed 's/X/0/g' <<< $1) # replace X with 0
    BEGIN=$(( $(sed 's/X/0/g' <<< $1) + $2))
    END=$(( $(sed 's/X/0/g' <<< $1) + $3))
    RANGE=`seq -w $BEGIN $END`
    for i in $RANGE
        do
            echo "[$i]($EXTENBLOCK)" >> "$SIP_CUSTOM_PATH"
    done
}

#########
# PJSIP #
#########

function PJSIPAOR {
    output "Generating AOR $1 $2 $3"
    EXTENBLOCK=$(sed 's/X/0/g' <<< $1) # replace X with 0
    BEGIN=$(( $(sed 's/X/0/g' <<< $1) + $2))
    END=$(( $(sed 's/X/0/g' <<< $1) + $3))
    RANGE=`seq -w $BEGIN $END`
    for i in $RANGE
        do
            echo "[$i](aor-$EXTENBLOCK)\nqualify_frequency=300" >> "$PJSIP_CUSTOM_PATH"
    done
}
function PJSIPAuth {
    output "Generating Auth $1 $2 $3"
    EXTENBLOCK=$(sed 's/X/0/g' <<< $1) # replace X with 0
    BEGIN=$(( $(sed 's/X/0/g' <<< $1) + $2))
    END=$(( $(sed 's/X/0/g' <<< $1) + $3))
    RANGE=`seq -w $BEGIN $END`
    for i in $RANGE
        do
            echo -e "[$i](auth-$EXTENBLOCK)\nusername=$i\npassword=`pwgen -1`" >> "$PJSIP_CUSTOM_PATH"
    done
}
function PJSIPEndpoint {
    output "Generating Endpoint $1 $2 $3"
    EXTENBLOCK=$(sed 's/X/0/g' <<< $1) # replace X with 0
    BEGIN=$(( $(sed 's/X/0/g' <<< $1) + $2))
    END=$(( $(sed 's/X/0/g' <<< $1) + $3))
    RANGE=`seq -w $BEGIN $END`
    for i in $RANGE
        do
            echo -e "[$i]($EXTENBLOCK)\ncallerid=$i\nauth=$i\naors=$i\ncontext=outbound" >> "$PJSIP_CUSTOM_PATH"
    done
}


#####################
# Config Generators #
#####################

function generateDialplan {
    output "Generating AEL dialplan files into $AEL_PATH based on input..."
    echo "" > $AEL_CUSTOM_PATH
    AELSpy
    AELOutbound
    hook=`grep -i 'extensions-custom' $AEL_PATH`
    if [[ $hook == "" ]]
    then
        echo "#include \"/etc/asterisk/extensions-custom.ael\"" >> $AEL_PATH
    fi
    output "Done generating AEL dialplan."
}
function generateSIP {
    output "Generating SIP config files into $SIP_PATH based on input..."
    echo "" > $SIP_CUSTOM_PATH
    arr=$(echo $PATTERNS | tr ";" "\n")
    for pattern in $arr
    do
        SIPPeerTemplate $pattern
        SIPPeer $pattern 1 $EXTENSIONS
    done
    hook=`grep -i 'sip-custom' $SIP_PATH`
    if [[ $hook == "" ]]
    then
        echo "#include /etc/asterisk/sip-custom.conf" >> $SIP_PATH
    fi
    output "Done generating SIP config files."
}
function generatePJSIP {
    output "Generating PJSIP config files into $PJSIP_PATH based on input..."
    echo "" > $PJSIP_CUSTOM_PATH
    arr=$(echo $PATTERNS | tr ";" "\n")
    for pattern in $arr
    do
        PJSIPAOR $pattern 1 $EXTENSIONS
        PJSIPAuth $pattern 1 $EXTENSIONS
        PJSIPEndpoint $pattern 1 $EXTENSIONS
    done
    hook=`grep -i 'pjsip-custom' $PJSIP_PATH`
    if [[ $hook == "" ]]
    then
        echo "#include /etc/asterisk/pjsip-custom.conf" >> $PJSIP_PATH
    fi
    output "Done generating PJSIP config files."
}

#################
# PROGRAM START #
#################

# Make sure only root can run our script
checkRoot

# Argument Switch Iterator (install flag, silent, config location, NO ARGUMENTS DEFAULTS TO HELP)
while getopts 'isf:' flag; do
  case "${flag}" in
    i) INSTALL='true' ;;
    s) SILENT='true' ;;
    f) CONFIG_LOCATION="${OPTARG}" ;;
    *) HELP='true' ;;
  esac
done

if [ -z "$HELP" ]
then
    if [ -z "$SILENT" ]
    then
        if [ -z "$INSTALL" ]
        then
            output "Install flag required to proceed."
        else
            # Install Asterisk
            installAsterisk

            # Prompt for Custom Values
            loadConfig
            walkthroughInstall

            # Generate Config Files
            generateDialplan
            if [[ $STACK == PJSIP* ]]
            then
                output "Stack chosen was PJSIP."
                generatePJSIP
            else
                output "Stack chosen was SIP."
                generateSIP
            fi

            # Start/Restart Asterisk
            restartAsterisk

            # Suggest Clients
            output "We recommend MicroSIP as a softphone, and SIPml5 if you're looking for a web solution to build into your site."
            output "If features matter most, Zoiper Classic is a softphone we recommend to those looking for a more robust solution."  
            output "You can find your user credentials in $SIP_CUSTOM_PATH or $PJSIP_CUSTOM_PATH."
        fi
    else # completely silent install
        loadConfig > /dev/null

        if [ -z "$INSTALL" ]
        then
            output "Install flag required to proceed."
        else
            if [ -z $CONFIG_LOCATION ] && [ -z $CONFIG ]
            then
                output "Config file required. Specify one or place one in local directory as asterisk_install.cfg."
            else
                installAsterisk > /dev/null

                generateDialplan > /dev/null
                if [[ $STACK == PJSIP* ]]
                then
                    generatePJSIP > /dev/null
                else
                    generateSIP > /dev/null
                fi

                restartAsterisk > /dev/null
            fi
        fi
    fi
else
    showHelp
fi

# Exit 0 - No Error
output "Success; end of installer."
exit 0

###############
# PROGRAM END #
###############
