//
// [Setsuden Now]
// Daily Electricity Consumption Meter
//
// Credit:
// * Originally written by Shigeru Kobayashi as GeigerCounterToPachube
//   (https://github.com/kotobuki/geiger-counter/tree/master/arduino/)
// * Modified by Takafumi Iwai
//   (https://github.com/tawashi5454/SetsudenNow)
//
// Hardware Connections:
// * Arduino Ethernet Shield
// * Wattmeter2 Arduino Shield by Galileo7
//   CT sensors should be attached to pin 1 and 2 in effective value setting
//   (http://www.galileo-7.com/?pid=20810906)
// 
// Software Requirements:
// * Time
//   (http://www.arduino.cc/playground/Code/Time)
// * EthernetDHCP, EthernetDNS
//   (http://gkaindl.com/software/arduino-ethernet)
// * Stewitter
//   (http://arms22.blog91.fc2.com/blog-entry-296.html)
// 
// References:
// * http://tumblr.ondra.cc/
// * http://arduino.cc/en/Tutorial/UdpNtpClient
// * http://www.yapan.org/main/2011/03/measure_radiation_dose.html
// * https://sites.google.com/a/galileoseven.com/galileo-7/home/wattmeter2
// * http://blog.galileo-7.com/?eid=125106
//

#include <Time.h>
#include <SPI.h>
#include <Ethernet.h>
#include <EthernetDHCP.h>
#include <EthernetDNS.h>
#include <math.h>
#include <Udp.h>
#include <Stewitter.h>

#include "PrivateSettings.h"

// Sensor Related Constants
#define CT ((330.0 * 0.99 / 3000.0) / (5.0 / 1024.0))
#define ANALOG_REFERENCE_PIN 0
#define ANALOG_SENSOR_1_PIN 1
#define ANALOG_SENSOR_2_PIN 2

// Electricity Consumption Related Variables
double electricityConsumption = 0.0; // Sum of electricity consumption during one Pachube loop
long electricityConsumptionCount = 0; // How many times electricity consumption was measured
double electricityConsumptionOfDay = 0.0; // Sum of electricity consumption during the day

// Timer Related Variables
unsigned long updateIntervalInMillis = 0; // Sampling interval (e.g. 60,000ms = 1min)
unsigned long nextExecuteMillis = 0; // The next time to feed
unsigned long lastConnectionMillis = 0; // The last connection time to disconnect from the server after uploaded feeds
unsigned int currentMinutesOfDay; // Minutes since the begenning of the day(e.g. 1035 at 5:15 pm)
unsigned long lastMeasureMillis; // The last time to measure electricity consumption
#define MAIN_LOOP_DURATION_MILLIS 1477 // Heuristic value of main loop duration. Used in case of overflowed millis()

// NTP Related Variables
#define NTP_PACKET_SIZE 48 // NTP time stamp is in the first 48 bytes of the message
#define LOCAL_UDP_PORT 8888 // local port to listen for UDP packets
byte timeServerIP[] = {192, 43, 244, 18}; // time.nist.gov NTP server
byte packetBuffer[NTP_PACKET_SIZE]; //buffer to hold incoming and outgoing packets 

// Pachube Related Variables
byte pachubeServerIP[] = {173, 203, 98, 29 }; // The IP address of api.pachube.com
Client client(pachubeServerIP, 80); // The TCP client
String csvData = ""; // The data to post

// Twitter Related Variables
Stewitter twitter(STEWITTER_TOKEN); // The twitter client
char dateString[15]; // Today's date in character representation

void setup() {
  delay(1000);

  Serial.begin(9600);
  setupEthernet();
  setupClock();

  updateIntervalInMillis = (UPDATE_INTERVAL_IN_MINUTE * 60000) - 1;
  nextExecuteMillis = millis() + updateIntervalInMillis;
  lastMeasureMillis = millis();
}

void setupEthernet(){
  // Initiate a DHCP session
  Serial.println("Getting an IP address...");
  EthernetDHCP.begin(macAddress);

  // We now have a DHCP lease, so we print out some information
  const byte* ipAddr = EthernetDHCP.ipAddress();
  Serial.print("IP address: ");
  Serial.print(ipAddr[0], DEC);
  Serial.print(".");
  Serial.print(ipAddr[1], DEC);
  Serial.print(".");
  Serial.print(ipAddr[2], DEC);
  Serial.print(".");
  Serial.print(ipAddr[3], DEC);
  Serial.println();

  Udp.begin(LOCAL_UDP_PORT);
  
  delay(1000);  
}

void setupClock(){
  updateClock();
  
  Serial.print(year(), DEC);
  Serial.print(" ");
  Serial.print(month(), DEC);
  Serial.print(" ");
  Serial.print(day(), DEC);
  Serial.print(" ");
  Serial.print(hour(), DEC);
  Serial.print(" ");
  Serial.print(minute(), DEC);
  Serial.print(" ");
  Serial.println(second(), DEC);
  
  currentMinutesOfDay = getCurrentMinutesOfDay();
  Serial.print("Current minutes of day: ");
  Serial.println(currentMinutesOfDay, DEC);

  setDateString();
}

void loop() {
  Serial.println("----Loop----");
  Serial.print("millis(): ");
  Serial.println(millis(), DEC);
  
  EthernetDHCP.maintain(); 
  loopMeasureElectricity();
  loopTwitter();
  loopPachube();
}

void loopMeasureElectricity(){
  float ec = measureElectricityConsumption();
  electricityConsumption += ec;
  electricityConsumptionCount += 1;
  
  if(millis() > lastMeasureMillis){ 
    electricityConsumptionOfDay += ec * (millis() - lastMeasureMillis) * 100 / 1000 / 3600;
  }else{
    // In case millis() was overflowed (about 50 days)
    electricityConsumptionOfDay += ec * MAIN_LOOP_DURATION_MILLIS * 100 / 1000 / 3600;
  }
  lastMeasureMillis = millis();
  
  Serial.print("electricityConsumption: ");
  Serial.println(electricityConsumption);
  Serial.print("electricityConsumptionCount: ");
  Serial.println(electricityConsumptionCount);
  Serial.print("electricityConsumptionOfDay: ");
  Serial.print(electricityConsumptionOfDay);
  Serial.println("Wh");
}

void loopTwitter(){
  char msg[256];

  if(currentMinutesOfDay > getCurrentMinutesOfDay()){
    
    float savedPercentage = 100.0 - (electricityConsumptionOfDay * 100 / USUAL_CONSUMPTION);
    
    electricityConsumptionOfDay /= 1000;
    int n1 = int(electricityConsumptionOfDay);
    int n2 = (electricityConsumptionOfDay - n1) * 10;
    int n3 = int(savedPercentage);
    int n4 = (savedPercentage - n3) * 10;
    sprintf(msg, "%sの消費電力は%d.%dkWhで、一般家庭の平均に比べて%d.%d%%の節電でした http://www.pachube.com/feeds/%d #setsuden_now", 
      dateString, n1, n2, n3, n4, PACHUBE_ENVIRONMENT_ID);

    if (twitter.post(msg)) {
      int status = twitter.wait();
      if (status == 200) {
        Serial.println("Posted successfully to Twitter");
      } else {
        Serial.print("Post failed to Twitter, code:");
        Serial.println(status);
      }
    } else {
        Serial.println("Connection failed to Twitter");
    } 
    
    updateClock();
    setDateString();
    electricityConsumptionOfDay = 0.0;

    delay(60 * 1000);
    currentMinutesOfDay = getCurrentMinutesOfDay();
  }
}

void loopPachube(){
  // Echo received strings to a host PC
  if (client.available()) {
    char c = client.read();
    Serial.print(c);
  }

  if ((millis() - lastConnectionMillis) > 5000) {
    if (client.connected()) {
      Serial.println("Disconnecting from Pachube.");
      client.stop();
    }
  }
  
  if (millis() > nextExecuteMillis) {
    float electricityConsumptionOfThisLoop = 
      electricityConsumption / electricityConsumptionCount;
    Serial.print("electricityConsumptionOfThisLoop: ");
    Serial.println(electricityConsumptionOfThisLoop);

    Serial.println("Updating to Pachube");
    updateDataStream(electricityConsumptionOfThisLoop);

    nextExecuteMillis = millis() + updateIntervalInMillis;
    electricityConsumption = 0.0;
    electricityConsumptionCount = 0;
  }
}




//****** Sub functions ******//




void updateDataStream(float consumption) {
  if (client.connected()) {
    Serial.println();
    Serial.println("Disconnecting from Pachube");
    client.stop();
  }

  // Try to connect to the server
  Serial.println();
  Serial.print("Connecting to Pachube...");
  if (client.connect()) {
    Serial.println("Connected to Pachube");
    lastConnectionMillis = millis();
  } else {
    Serial.println("Connection failed to Pachube");
    return;
  }

  csvData = "";
  csvData += "0,";
  appendFloatValueAsString(csvData, consumption);
  Serial.println(csvData);

  client.print("PUT /v2/feeds/");
  client.print(PACHUBE_ENVIRONMENT_ID);
  client.println(" HTTP/1.1");
  client.println("User-Agent: Arduino");
  client.println("Host: api.pachube.com");
  client.print("X-PachubeApiKey: ");
  client.println(PACHUBE_API_KEY);
  client.print("Content-Length: ");
  client.println(csvData.length());
  client.println("Content-Type: text/csv");
  client.println();
  client.println(csvData);
}

// Since "+" operator doesn't support float values,
// convert a float value to a fixed point value
void appendFloatValueAsString(String& outString,float value) {
  int integerPortion = (int)value;
  int fractionalPortion = (value - integerPortion + 0.0005) * 1000;

  outString += integerPortion;
  outString += ".";

  if (fractionalPortion < 10) {
    // e.g. 9 > "00" + "9" = "009"
    outString += "00";
  } 
  else if (fractionalPortion < 100) {
    // e.g. 99 > "0" + "99" = "099"
    outString += "0";
  }

  outString += fractionalPortion;
}

float measureElectricityConsumption() {
  int i;

  int ref = analogRead(ANALOG_REFERENCE_PIN);
  float ave1 = 0;
  float ave2 = 0;

  for (i = 0; i < 5000; i ++) {
    float ad1 = analogRead(ANALOG_SENSOR_1_PIN) - ref;
    float ad2 = analogRead(ANALOG_SENSOR_2_PIN) - ref;
    ave1 = ave1 + (ad1 * ad1);
    ave2 = ave2 + (ad2 * ad2);
  }

  float a1 = sqrt(ave1 / i) / CT;
  float a2 = sqrt(ave2 / i) / CT;
  float result = a1 + a2;
  
  Serial.print("measureElectricityConsumption(): ");
  Serial.print(result);
  Serial.println("A");
  
  return result;
}

void updateClock(){
  // send an NTP packet to a time server
  sendNTPpacket(timeServerIP); 

  // wait for the reply
  delay(1000);
  while(!Udp.available()){
    Serial.println("No NTP reply, waiting...");
    delay(100);  
  }
  
  // read the packet into the buffer
  Udp.readPacket(packetBuffer,NTP_PACKET_SIZE);

  // the timestamp starts at byte 40 of the received packet and is four bytes,
  // or two words, long. First, esxtract the two words:
   unsigned long highWord = word(packetBuffer[40], packetBuffer[41]);
   unsigned long lowWord = word(packetBuffer[42], packetBuffer[43]);  
  // combine the four bytes (two words) into a long integer
  // this is NTP time (seconds since Jan 1 1900):
  unsigned long secsSince1900 = highWord << 16 | lowWord;  
  // Time zone offset
  secsSince1900 += TIME_ZONE_OFFSET * 60 * 60;

  // now convert NTP time into everyday time:
  // Unix time starts on Jan 1 1970. In seconds, that's 2208988800:
  const unsigned long seventyYears = 2208988800UL;     
  // subtract seventy years:
  unsigned long epoch = secsSince1900 - seventyYears;  
  Serial.print("Unix time = ");
  Serial.println(epoch);    

  // Set the Clock
  setTime(epoch);
}

// send an NTP request to the time server at the given address 
unsigned long sendNTPpacket(byte *address)
{
  Serial.println("Sending NTP packet");
  
  // set all bytes in the buffer to 0
  memset(packetBuffer, 0, NTP_PACKET_SIZE); 
  // Initialize values needed to form NTP request
  // (see URL above for details on the packets)
  packetBuffer[0] = 0b11100011;   // LI, Version, Mode
  packetBuffer[1] = 0;     // Stratum, or type of clock
  packetBuffer[2] = 6;     // Polling Interval
  packetBuffer[3] = 0xEC;  // Peer Clock Precision
  // 8 bytes of zero for Root Delay & Root Dispersion
  packetBuffer[12]  = 49; 
  packetBuffer[13]  = 0x4E;
  packetBuffer[14]  = 49;
  packetBuffer[15]  = 52;
  
  // all NTP fields have been given values, now
  // you can send a packet requesting a timestamp:         
  Udp.sendPacket( packetBuffer,NTP_PACKET_SIZE,  address, 123); //NTP requests are to port 123
}

int getCurrentMinutesOfDay(){
  return hour() * 60 + minute();
}

void setDateString(){
  sprintf(dateString, "%d/%d/%d", year(), month(), day());
}
