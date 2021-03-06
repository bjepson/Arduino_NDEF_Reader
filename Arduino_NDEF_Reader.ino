/*
 Arduino RFID SM130 NDEF reader

 May 2011
 Brian Jepson
 
 This program will seek for tags when it is given the command 's' over serial.
 It will then attempt to read the NDEF-formatted URL in Sector 1, and sends the
 payload (prefixed by a U) over the serial port. 
 
 It can also be told to turn a success LED on (+) or a failure LED on (-).
 
 This example cannot read NDEF messages that span multiple sectors.
 
 Based on Arduino RFID SM130 reader example
 created May 2008
 by Alex Zivanovic (www.zivanovic.co.uk)
 modified March 2009
 by Tom Igoe
 
 */

#include <Wire.h>
#include <EEPROM.h>

// define the LED pins:
#define waitingLED 11
#define successLED 12
#define failureLED 13

int toggleState = 0;    // state of the toggling LED
long toggleTime = 0;    // delay time of the toggling LED

int payloadSector = 1; // which sector to read
int payloadBlock  = payloadSector * 4;

byte responseBuffer[256]; // To hold the last response from the reader

void setup() {           
  Serial.begin(9600);                // set up serial port

  Wire.begin();                      // join i2c bus 
  delay(1500);
  
  Wire.beginTransmission(0x42);      // the RFID reader's address is 42
  Wire.write(0x01);                   // Length
  Wire.write(0x80);                   // reset reader 
  Wire.write(0x81);                   // Checksum
  Wire.endTransmission();            

  // delay to allow reader startup time:
  delay(1500);

  // initialize the LEDs:
  pinMode(waitingLED, OUTPUT);
  pinMode(successLED, OUTPUT);
  pinMode(failureLED, OUTPUT);

  
  // FIXME - send something out over serial when we're warmed up.
} 


void loop() {

  if (Serial.available() > 0) {
    
    // read the latest byte:
    char incomingByte = Serial.read();   
    switch (incomingByte) {
    case 's':            // Look for a new tag
      seekNewTag();
      break;  
    case '-': // you haven't tweeted!
      digitalWrite(failureLED, HIGH);
      break;
    case '+': // good for you!
      digitalWrite(successLED, HIGH);
      break;
    }
  }

  // delay before next command to the reader:
  delay(200);
}

void seekNewTag() {
  
  // Clear the indicator LEDs
  digitalWrite(failureLED, LOW);
  digitalWrite(successLED, LOW);

  Serial.print("READY"); // FIXME--change to something that indicates we're seeking. 
  while(getTag() == 0){
    // wait for tag
    if (millis() - toggleTime > 1000) {
      toggle(waitingLED); 
      toggleTime  = millis();
    }
    // If you get a byte of serial data, we've received another command.
    if (Serial.available()) {
      // So, break out of the while loop 
      // and out of the seekNewTag() method:
      return;
    }
  }

  // Try to authenticate
  //
  int result = authenticate(payloadBlock);
  if (result > 0) {
    delay(100); // give it a moment
    
    // Read the payload contained in this sector.
    String payload = getPayload(payloadBlock);
    if (payload.length() > 0) {
      // Return the payload to the client
      Serial.print('U');
      Serial.print(payload); 
    } else {
      Serial.print("N"); // Got nothin' for ya pal
    }
  } 
  else {
    Serial.print("F"); // Authentication Failed
  }

}


// Authenticate yourself to the tag.
//
int authenticate(int block) {

  int length = 9;
  int command[] = {
    0x85,  // authenticate
    block,
    0xBB,  // Key B
    0xFF,  // The rest are the keys
    0xFF,
    0xFF,
    0xFF,
    0xFF,
    0xFF,
  };  
  sendCommand(command, length); 

  getResponse(4);
  if (responseBuffer[2] == 0x4C) {
    return 1;
  } 
  else {
    if (responseBuffer[2] == 0x4E) {
      return 0; // no tag or login failed
    }
    if (responseBuffer[2] == 0x55) {
      return -1; // login failed
    }
    if (responseBuffer[2] == 0x45) {
      return -2; // invalid key format
    }
  }

}

// Seek for tags. 
int getTag(){

  byte byteFromReader = 0;

  int length = 1;
  int command[] = {
    0x82,  // Seek for tags
  };
  sendCommand(command, length);  

  int count = getResponse(8); // get data (8 bytes) from reader
  if (responseBuffer[2] == 0x4C) {
    return 0;
  } else if (responseBuffer[2] == 0x55) {
    //Serial.println("FIXME: you need to power up the RF field!");
    return 0; // FIXME--need to power up the RF field!!
  } else {
    return 1;
  }

}

// Read a single-sector payload. The reader sends back a response that
// includes 3 bytes (data length, command, block number) in addition 
// to 16 bytes of data, for a total of 19 bytes. In the first block,
// the payload starts after a bunch of other block metadata. In the 
// remaining blocks, the payload continues immediately after those 3
// initial bytes.
//
String getPayload(int startBlock) {

  int length = 0;
  String payLoad = "";

  int startByte = 0;
  for (int i = 0; i < 3; i++) { // Check all three blocks

    if (readBlock(startBlock + i) == 20) {
      if (i == 0) {
        length = responseBuffer[9];
        startByte = 12;  // offset of payload in first block response
      } 
      else {
        startByte = 3;  // ofset of payload in next 2 block responses
      }

      for (int j = startByte; j < 19; j++) {
        if (--length > 0) { // Keep adding characters until we reach the length.
          payLoad += (char) responseBuffer[j];
          //Serial.print(j);
          //Serial.print(" = ");
          //Serial.write(responseBuffer[j]);
          //Serial.println();

        }
      }

    }
  }
  return payLoad;
}

// Read a block. You need to authenticate() before you can call this.
//
int readBlock(int block) {

  int length = 2;
  int command[] = {
    0x86,  // read block
    block, 
  };
  sendCommand(command, length);  

  int count = getResponse(20);  // get 20 bytes (3 response + 16 data + checksum)
  if (responseBuffer[2] == 0x4E) {
    // No tag present
    return 0;
  } 
  else if (responseBuffer[2] == 0x46) {
    // Read failed
    return 0;
  }

  return count;
}

// Send a command to the reader
//
void sendCommand(int command[], int length) {

  Wire.beginTransmission(0x42); 
  
  int checksum = length; // Starting value for the checksum.
  
  Wire.write(length);
  
  for (int i = 0; i < length; i++) {
    checksum += command[i]; // Add each byte to the checksum
    Wire.write(command[i]);
  }
  
  checksum = checksum % 256; // mod the checksum then send it
  Wire.write(checksum);

  Wire.endTransmission();
  delay(25);
  
}

// Retrieve a response from the reader.
//
int getResponse(int numBytes) {

  Wire.requestFrom(0x42, numBytes); // get response from reader

  int c = 10;
  while(!Wire.available() && c--) {
   delay(50);
  }
  int count = 0;
  while(Wire.available())  { // while data is coming from the reader
    byte read = Wire.read();
    //Serial.print(read, HEX);
    //Serial.print(" = ");
    //Serial.write(read);
    //Serial.println("");
    //delay(1);
    responseBuffer[count++] = read;
  }  
  responseBuffer[count] = 0;

  return count;

}

// Toggle the LED.
//
void toggle(int thisLED) {
  toggleState = !toggleState;
  digitalWrite(thisLED, toggleState);
}

// Blink an LED.
//
void blink(int thisLED, int interval, int count) {
  for (int i = 0; i < count; i++) {
    digitalWrite(thisLED, HIGH);
    delay(interval/2);
    digitalWrite(thisLED, LOW);
    delay(interval/2);
  }
}
