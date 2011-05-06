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
  seekNewTag(); 

  // delay before next command to the reader:
  delay(200);
}

int authenticate(int block) {
  
  byte valid = 0;
  byte byteFromReader = 0;
  
  Serial.println("== Beginning authentication");

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
  
  Wire.requestFrom(0x42, 4); // get response (4 bytes) from reader

  while(Wire.available())  { // while data is coming from the reader
    byteFromReader = Wire.receive();
    Serial.println(byteFromReader, HEX);
    if (byteFromReader == 0x4C) { 
      Serial.println("Authentication OK");
      valid = 1;
    }
    if (byteFromReader == 0x4E) { 
      Serial.println("Authentication failed");
      valid = 0;
    }
  }  
  return valid;
}

int readBlock(int block) {
  
  byte valid = 0;
  byte byteFromReader = 0;
  Serial.println("== Reading block");

  int length = 2;
  int command[] = {
    0x86,  // read block
    block, 
  };
  sendCommand(command, length);  


  Wire.requestFrom(0x42, 20); // get 20 bytes (3 response + 16 data + checksum)

  while(Wire.available())  { // while data is coming from the reader
    byteFromReader = Wire.receive();
    Serial.println(byteFromReader, HEX);
    if (byteFromReader == 0x4E) { 
      Serial.println("No tag present");
      valid = 0;
    }
    if (byteFromReader == 0x46) { 
      Serial.println("Read failed");
      valid = 0;
    }
  }  
  return valid;
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

  Wire.requestFrom(0x42, 8); // get data (8 bytes) from reader

  count = 0;                 // keeps track of which byte it is in the response from the reader
  valid = 0;                 // used to indicate that there is a tag there   
  while(Wire.available())  { // while data is coming from the reader
    byteFromReader = Wire.receive();
    // no RFID found: reader sends character 2:
    if ((count == 0) && (byteFromReader == 2)) { 
      return(0);
    }
    if ((count == 0) && (byteFromReader== 6)) {
      //if reader sends 6, the tag serial number is coming:
      valid = 1;                                   
    }
    count++;

    if ((valid == 1) && (count > 3) && (count < 8)) {
      // strip out the header bytes  :
      tag[count-4] = byteFromReader;            
    }
    // all four bytes received: tag serial number complete:
    if ((valid == 1) && (count == 8)) {         
      return(1);
    }
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

void seekNewTag() {
  Serial.println("Waiting for card");
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
  authenticate(4);
  delay(100);
  readBlock(4);
  delay(100);
  readBlock(5);
  blink(successLED, 100, 1);

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

