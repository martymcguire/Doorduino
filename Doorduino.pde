// RFID Reader with RTC timestamping and door driving!
// Reports, via Serial, any RFID tags found along with timestamp and whether
// or not the tag was in the tag database.
// Also supports some commands over Serial:
//  - 'L' - Lists tags in the database, one per line
//  - 'U<#tags><tagdata>' - Accepts a new list of tags 
//                          (first byte # of tags, each tag is 10 chars
//  - [TODO] 'T<timedata>' - Set the clock YMDWhms
// Kludged together by Marty McGuire <http://creatingwithcode.com/>
// NOTE: Broken because SoftwareSerial doesn't support SS.available()!!!!

// DS1307 demo
// -- Found at http://www.arduino.cc/cgi-bin/yabb2/YaBB.pl?num=1198881858
// -- by Jon McPhalen (www.jonmcphalen.com) -- based on work by others
// -- 29 DEC 2007
// SDA pin is Analog4
// SCL pin is Analog5
// Relay pin is Digital5

// Parallax RFID demo
// Modified by Worapoht K.
// Found at http://www.arduino.cc/playground/Learning/PRFID
// RX uses Serial (Pin 0)
// /ENABLE on Digital2

#include <Wire.h>
#include <SoftwareSerial.h>
#include <EEPROM.h>
#include <RFIDDB.h>

// Door is on Digital 5
#define RELAY       5
#define DS1307      0xD0 >> 1                   // shift required by Wire.h (silly...)

// DS1307 clock registers
#define R_SECS      0
#define R_MINS      1
#define R_HRS       2
#define R_WKDAY     3
#define R_DATE      4
#define R_MONTH     5
#define R_YEAR      6
#define R_SQW       7

// RFID reader SOUT pin connected to Serial RX (pin 3) at 2400bps
// /ENABLE on Digital2
#define RFID_DISABLE 2
#define RFID_RX 3
#define RFID_TX 4

// RTC reading vars
byte second = 0x00;                             // default to 01 JAN 2007, midnight
byte minute = 0x00;
byte   hour = 0x00;
byte  wkDay = 0x02;
byte    day = 0x01;
byte  month = 0x01;
byte   year = 0x07;
byte   ctrl = 0x00;

// RFID reader vars
int  val = 0; 
char code[10]; 
int  bytesread = 0;

// RFIDDB
RFIDDB rfiddb;

// Admin flag
boolean adminMode;

void setup()
{
  Wire.begin();
  Serial.begin(9600);
  
  pinMode(RELAY, OUTPUT);
  digitalWrite(RELAY, LOW);
  
  pinMode(RFID_DISABLE, OUTPUT);      // Set digital pin 2 as OUTPUT to connect it to the RFID /ENABLE pin 
  digitalWrite(RFID_DISABLE, HIGH);   // Disable the RFID reader 

  rfiddb = RFIDDB();
  
  adminMode = true;
  Serial.println("Door is Ready");
}

void loop()
{ 
  if(adminMode) {
    if(Serial.available() > 0){
      handleCommand();
    } else {
      delay(10);
    }
  } else {
      readTag(); // blocks
  }
  
  if(millis() > 10000){ // 10 seconds
    adminMode = false;
    digitalWrite(RFID_DISABLE, LOW);   // Activate the RFID reader 
  }
}

void handleCommand()
{
  char inByte = Serial.read();
  switch(inByte){
    case 'U':
      Serial.println("Upload time!");
      rfiddb.readTags();
      break;
    case 'L':
      rfiddb.printTags();
      break;
    case 'T':
      setTimeFromSerial();
      break;
  }
}

void readTag()
{
  SoftwareSerial RFID = SoftwareSerial(RFID_RX, RFID_TX);
  RFID.begin(2400);
  boolean allowed = 0;
  
  if((val = RFID.read()) == 10)
  {   // check for header 
    bytesread = 0; 
    while(bytesread<10)
    {  // read 10 digit code 
      val = RFID.read(); 
      if((val == 10)||(val == 13))
      {  // if header or stop bytes before the 10 digit reading 
        break;                       // stop reading 
      } 
      code[bytesread] = val;         // add the digit           
      bytesread++;                   // ready to read next digit  
    } 

    if(bytesread == 10)
    {  // if 10 digit read is complete 
      getClock();
      allowed = rfiddb.validTag(code);
      logTag(allowed);
      if(allowed) {
         openDoor();
      } else {
         rejectTag();
      }
    }
    bytesread = 0; 
    delay(500);                       // wait for a bit
  } 

}

void logTag(boolean allowed)
{
  Serial.print("TAG code ");   // possibly a good TAG 
  for(int i = 0; i < 10; i++){ // print the TAG code
    Serial.print(code[i]);      
  }
  if(allowed){ Serial.print(" GRANTED"); }
  else {       Serial.print(" DENIED");  }
      
  Serial.print(" access at ");
  printTime();
  Serial.println();
}

void rejectTag()
{
  for(int i = 0; i < 3; i++){
    digitalWrite(RFID_DISABLE, HIGH);
    delay(500);
    digitalWrite(RFID_DISABLE, LOW);
    delay(500);  
  }
}

void openDoor()
{
 
  digitalWrite(RELAY, HIGH);
  digitalWrite(RFID_DISABLE, HIGH);
  delay(5000);
  digitalWrite(RELAY, LOW);
  digitalWrite(RFID_DISABLE, LOW); 
}

void printTime()
{
  printHex2(hour);
  Serial.print(":");
  printHex2(minute);
  Serial.print(":");
  printHex2(second);
  Serial.print("  ");
  printDayName(bcd2Dec(wkDay));
  Serial.print("  ");
  printHex2(day);
  Serial.print(" ");
  printMonthName(bcd2Dec(month));
  Serial.print(" 20");
  printHex2(year);
}

void setClock()
{
  Wire.beginTransmission(DS1307);
  Wire.send(R_SECS);
  Wire.send(second);
  Wire.send(minute);
  Wire.send(hour);
  Wire.send(wkDay);
  Wire.send(day);
  Wire.send(month);
  Wire.send(year);
  Wire.send(ctrl);
  Wire.endTransmission();
}

void setTimeFromSerial()
{
  second = 255;
  minute = 255;
  hour   = 255;
  wkDay  = 255;
  day    = 255;
  month  = 255;
  year   = 255;
  boolean done = false;
  while(!done){
    if(Serial.available() > 0){
      if(year == 255){
        year = dec2Bcd(Serial.read());
      } else if (month == 255) {
        month = dec2Bcd(Serial.read());
      } else if (day == 255) {
        day = dec2Bcd(Serial.read());
      } else if (wkDay == 255) {
        wkDay = dec2Bcd(Serial.read() + 1);
      } else if (hour == 255) {
        hour = dec2Bcd(Serial.read());
      } else if (minute == 255) {
        minute = dec2Bcd(Serial.read());
      } else {
        second = dec2Bcd(Serial.read());
        done = true;
      }
    }
  }
  setClock();
  getClock();
  Serial.print("Time Set: ");
  printTime();
  Serial.println();
}

void getClock()
{
  Wire.beginTransmission(DS1307);
  Wire.send(R_SECS);
  Wire.endTransmission();
  Wire.requestFrom(DS1307, 8);
  second = Wire.receive();
  minute = Wire.receive();
  hour   = Wire.receive();
  wkDay  = Wire.receive();
  day    = Wire.receive();
  month  = Wire.receive();
  year   = Wire.receive();
  ctrl   = Wire.receive();
}


byte bcd2Dec(byte bcdVal)
{
  return bcdVal / 16 * 10 + bcdVal % 16;
}

byte dec2Bcd(byte decVal)
{
  return decVal / 10 * 16 + decVal % 10;
}


void printHex2(byte hexVal)
{
  if (hexVal < 0x10)
    Serial.print("0");
  Serial.print(hexVal, HEX);
}


void printDec2(byte decVal)
{
  if (decVal < 10)
    Serial.print("0");
  Serial.print(decVal, DEC);
}


void printDayName(byte d)
{
  switch (d) {
    case 1:
      Serial.print("SUN");
      break;
    case 2:
      Serial.print("MON");
      break;
    case 3:
      Serial.print("TUE");
      break;
    case 4:
      Serial.print("WED");
      break;
    case 5:
      Serial.print("THU");
      break;
    case 6:
      Serial.print("FRI");
      break;
    case 7:
      Serial.print("SAT");
      break;
    default:
      Serial.print("???");
  }
}


void printMonthName(byte m)
{
  switch (m) {
    case 1:
      Serial.print("JAN");
      break;
    case 2:
      Serial.print("FEB");
      break;
    case 3:
      Serial.print("MAR");
      break;
    case 4:
      Serial.print("APR");
      break;
    case 5:
      Serial.print("MAY");
      break;
    case 6:
      Serial.print("JUN");
      break;
    case 7:
      Serial.print("JUL");
      break;
    case 8:
      Serial.print("AUG");
      break;
    case 9:
      Serial.print("SEP");
      break;
    case 10:
      Serial.print("OCT");
      break;
    case 11:
      Serial.print("NOV");
      break;
    case 12:
      Serial.print("DEC");
      break;
    default:
      Serial.print("???");
  }
}
