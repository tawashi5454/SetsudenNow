// Connection:
// * An Arduino Ethernet Shield
// * D3: The output pin of the Geiger counter (active low)
// 
// Requirements:
// EthernetDHCP
// http://gkaindl.com/software/arduino-ethernet
// 
// Reference:
// * http://www.sparkfun.com/products/9848

#include <SPI.h>
#include <Ethernet.h>
#include <EthernetDHCP.h>

#include "PrivateSettings.h"

// The IP address of api.pachube.com
byte serverIpAddress[] = { 
  173, 203, 98, 29 };

// The TCP client
Client client(serverIpAddress, 80);

String csvData = "";

// Sampling interval (60,000ms = 1min)
const unsigned int samplingInterval = 59999;

// The next time to feed
unsigned long nextExecuteMillis = 0;

// Value to store counts per minute
int count = 0;

// The last connection time to disconnect from the server
// after uploaded feeds
long lastConnectionTime = 0;

void setup() {
  Serial.begin(9600);

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

  // Attach an interrupt to the digital pin and start counting
  // 
  // Note:
  // Most Arduino boards have two external interrupts: 
  // numbers 0 (on digital pin 2) and 1 (on digital pin 3)
  attachInterrupt(1, onPulse, FALLING);
  nextExecuteMillis = millis() + samplingInterval;
}

void loop() {
  // Periodically call this method to maintain your DHCP lease
  EthernetDHCP.maintain();

  // Echo received strings to a host PC
  if (client.available()) {
    char c = client.read();
    Serial.print(c);
  }

  if ((millis() - lastConnectionTime) > 5000) {
    if (client.connected()) {
      Serial.println("Disconnecting.");
      client.stop();
    }
  }

  if (millis() > nextExecuteMillis) {
    Serial.println();
    Serial.println("Updating...");

    int countsPerMinute = count;
    count = 0;

    updateDataStream(countsPerMinute);
    nextExecuteMillis = millis() + samplingInterval;
  }
}

// On each falling edge of the Geiger counter's output, 
// increment the counter
void onPulse() {
  count++;
}

void updateDataStream(int countsPerMinute) {
  if (client.connected()) {
    Serial.println();
    Serial.println("Disconnecting.");
    client.stop();
  }

  // Try to connect to the server
  Serial.println();
  Serial.print("Connecting to Pachube...");
  if (client.connect()) {
    Serial.println("connected");
    lastConnectionTime = millis();
  }
  else {
    Serial.println("failed");
    return;
  }

  float microsievertPerHour = (float)countsPerMinute * 0.002333;

  // Since "+" operator doesn't support float values,
  // convert a float value to a fixed point value
  int integerPortion = (int)microsievertPerHour;
  int fractionalPortion = (microsievertPerHour - integerPortion + 0.0005) * 1000;

  csvData = "";
  csvData += "0,";
  csvData += countsPerMinute;
  csvData += "\n";
  csvData += "1,";
  csvData += integerPortion;
  csvData += ".";

  if (fractionalPortion < 10) {
    // e.g. 9 > "00" + "9" = "009"
    csvData += "00";
  } 
  else if (fractionalPortion < 100) {
    // e.g. 99 > "0" + "99" = "099"
    csvData += "0";
  }

  csvData += fractionalPortion;

  Serial.println(csvData);

  client.print("PUT /v2/feeds/");
  client.print(environmentId);
  client.println(" HTTP/1.1");
  client.println("User-Agent: Arduino");
  client.println("Host: api.pachube.com");
  client.print("X-PachubeApiKey: ");
  client.println(apiKey);
  client.print("Content-Length: ");
  client.println(csvData.length());
  client.println("Content-Type: text/csv");
  client.println();
  client.println(csvData);
}

