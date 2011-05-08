/*
Arduino RFID SM130 reader example 
 
 This program implements an RFID card reader and on-chip storage system
 RFID tags are saved to the database by sending a "n" character serially to the Arduino
 Tags subsequently presented to the reader are checked to see if they are the database 
 
 The database is saved in EEPROM so that it is available after a reset or power cycle
 The complete database is erased by typing "c". 
 Individual cards are erased by typing "d", then presenting the RFID tag.
 The list of tags in the database can be seen by typing "p"
 
 created May 2008
 by Alex Zivanovic (www.zivanovic.co.uk)
 
 modified March 2009
 by Tom Igoe
 
 modified May 2011
 by Brian Jepson
 */

#include <Wire.h>
#include <EEPROM.h>

// There are 512 bytes of EEPROM available. The data stored there 
//remains when the Arduino is switched off or reset
// Each tag uses 5 bytes (1 byte status, 4 bytes tag number), 
//so 512 / 5 = 102 cards may be stored

#define MAX_NO_CARDS 102 


// define the LED pins:
#define waitingLED 7
#define successLED 8
#define failureLED 9

int toggleState = 0;    // state of the toggling LED
long toggleTime = 0;    // delay time of the toggling LED
byte tag[4];            // tag serial numbers are 4 bytes long

byte responseBuffer[256];

void setup() {           
  Wire.begin();                      // join i2c bus  
  Serial.begin(9600);                // set up serial port

  Wire.beginTransmission(0x42);      // the RFID reader's address is 42
  Wire.send(0x01);                   // Length
  Wire.send(0x80);                   // reset reader 
  Wire.send(0x81);                   // Checksum
  Wire.endTransmission();            

  // initialize the LEDs:
  pinMode(waitingLED, OUTPUT);
  pinMode(successLED, OUTPUT);
  pinMode(failureLED, OUTPUT);

  // delay to allow reader startup time:
  delay(2000);
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
  digitalWrite(failureLED, LOW);
  digitalWrite(successLED, LOW);

  Serial.print("READY");
  while(getTag() == 0){
    // wait for tag
    if (millis() - toggleTime > 1000) {
      toggle(waitingLED); 
      toggleTime  = millis();
    }
    // unless you get a byte of serial data,
    if (Serial. available()) {
      // break out of the while loop 
      // and out of the seekNewTag() method:
      return;
    }
  }

  if (!authenticate(4)) {
    Serial.print("F"); // Authentication Failed
  } 
  else {

    delay(100);
    String payload = getPayload(4);
    if (payload.length() > 0) {
      Serial.print('U');
      Serial.print(payload); 
    }
  }

}


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
    // No tag or login failed
    return 0;
  }

}

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

int getTag(){
  byte count = 0;
  byte valid = 0;
  byte byteFromReader = 0;

  int length = 1;
  int command[] = {
    0x82,  // Seek for tags
  };
  sendCommand(command, length);  

  getResponse(8); // get data (8 bytes) from reader
  if (responseBuffer[0] == 2) {
    return 0;
  } 
  else {
    return 1;
  }

}

void sendCommand(int command[], int length) {

  Wire.beginTransmission(0x42); 
  int checksum = length;
  Wire.send(length);
  for (int i = 0; i < length; i++) {
    checksum += command[i];
    Wire.send(command[i]);
  }
  checksum = checksum % 256;
  Wire.send(checksum);
  Wire.endTransmission();
  delay(100);
}

int getResponse(int numBytes) {

  Wire.requestFrom(0x42, numBytes); // get response (4 bytes) from reader

  int count = 0;
  while(Wire.available())  { // while data is coming from the reader
    byte read = Wire.receive();
    responseBuffer[count++] = read;
  }  
  responseBuffer[count] = 0;

  return count;

}

String getPayload(int startBlock) {

  int length = 0;
  String payLoad = "";

  int startByte = 0;
  for (int i = 0; i < 3; i++) { // Check all three blocks

    if (readBlock(startBlock + i) == 20) {
      if (i == 0) {
        length = responseBuffer[9];
        startByte = 12;  // offset of payload in first block
      } 
      else {
        startByte = 3;  // ofset of payload in next 2 blocks
      }

      for (int j = startByte; j < 19; j++) {
        if (--length > 0) { // Keep adding characters until we reach the length.
          payLoad += responseBuffer[j];
        }
      }

    }
  }
  return payLoad;
}


void toggle(int thisLED) {
  toggleState = !toggleState;
  digitalWrite(thisLED, toggleState);
}

void blink(int thisLED, int interval, int count) {
  for (int i = 0; i < count; i++) {
    digitalWrite(thisLED, HIGH);
    delay(interval/2);
    digitalWrite(thisLED, LOW);
    delay(interval/2);
  }
}






