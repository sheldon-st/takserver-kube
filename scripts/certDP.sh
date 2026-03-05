#!/bin/bash
# Makes an ATAK / iTAK friendly data package containing CA, user cert, user key
if [ $# -eq 0 ]; then
    echo "No arguments supplied. Need an IP and a user eg. ./certDP.sh 192.168.0.2 user1"
    exit
fi

IP=$1
USER=$2

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# server.pref
cat > server.pref <<PREF
<?xml version='1.0' encoding='ASCII' standalone='yes'?>
<preferences>
  <preference version="1" name="cot_streams">
    <entry key="count" class="class java.lang.Integer">1</entry>
    <entry key="description0" class="class java.lang.String">TAK Server</entry>
    <entry key="enabled0" class="class java.lang.Boolean">true</entry>
    <entry key="connectString0" class="class java.lang.String">$IP:8089:ssl</entry>
  </preference>
  <preference version="1" name="com.atakmap.app_preferences">
    <entry key="displayServerConnectionWidget" class="class java.lang.Boolean">true</entry>
    <entry key="caLocation" class="class java.lang.String">cert/$IP.p12</entry>
    <entry key="caPassword" class="class java.lang.String">atakatak</entry>
    <entry key="clientPassword" class="class java.lang.String">atakatak</entry>
    <entry key="certificateLocation" class="class java.lang.String">cert/$USER.p12</entry>
  </preference>
</preferences>
PREF

# manifest.xml
cat > manifest.xml <<MANIFEST
<MissionPackageManifest version="2">
  <Configuration>
    <Parameter name="uid" value="sponsored-by-cloudrf-the-api-for-rf"/>
    <Parameter name="name" value="$USER DP"/>
    <Parameter name="onReceiveDelete" value="true"/>
  </Configuration>
  <Contents>
    <Content ignore="false" zipEntry="certs\\server.pref"/>
    <Content ignore="false" zipEntry="certs\\$IP.p12"/>
    <Content ignore="false" zipEntry="certs\\$USER.p12"/>
  </Contents>
</MissionPackageManifest>
MANIFEST

zip -j "$PROJECT_DIR/tak/certs/files/$USER-$IP.dp.zip" manifest.xml server.pref "$PROJECT_DIR/tak/certs/files/$IP.p12" "$PROJECT_DIR/tak/certs/files/$USER.p12"
rm -f server.pref manifest.xml
echo "-------------------------------------------------------------"
echo "Created certificate data package for $USER @ $IP as tak/certs/files/$USER-$IP.dp.zip"
