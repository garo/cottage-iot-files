/*
  ESP8266 Blink by Simon Peter
  Blink the blue LED on the ESP-01 module
  This example code is in the public domain

  The blue LED on the ESP-01 module is connected to GPIO1
  (which is also the TXD pin; so we cannot use Serial.print() at the same time)

  Note that this sketch uses LED_BUILTIN to find the pin with the internal LED
*/

#include <ESP8266WiFi.h>
#include <LiquidCrystal_I2C.h>
#include <PubSubClient.h>

#define BUZZER_PIN 14

LiquidCrystal_I2C lcd(0x3F, 16, 2);

byte up_arrow[8] = {
  B00100,
  B01110,
  B10101,
  B00100,
  B00100,
  B00100,
  B00100,
};

byte down_arrow[8] = {
  B00100,
  B00100,
  B00100,
  B00100,
  B10101,
  B01110,
  B00100,
};

const char* ssid = "my-ssid";
const char* password = "";
const char* mqtt_server = "";
const int mqtt_port = 1883;
byte beeps = 0;
byte rolling_pos = 0;
const char rolling[] = "|/-\\";

String path = "nest/displays/";
unsigned long last_message_time = 0;

WiFiClient espClient;
PubSubClient client(espClient);

void callback(char* topic, byte* payload, unsigned int length) {
  Serial.print("Message arrived [");
  Serial.print(topic);
  Serial.print("] ");
  String str("                    ");
  for (int i = 0; i < length; i++) {
    Serial.print((char)payload[i]);
    str[i] = (char)payload[i];
  }
  Serial.println();

  String subpath(topic);
  subpath = subpath.substring(path.length() - 1);
  Serial.println("subpath: " + subpath);

  if (subpath != 0 && subpath.equals("backlight")) {
    if ((char)payload[0] == '1') {
      lcd.backlight();
    } else if ((char)payload[0] == '0') {
      lcd.noBacklight();
    }
  }


  if (subpath != 0 && subpath.equals("r0")) {
    last_message_time = millis();  
    lcd.setCursor(0, 0);
    lcd.print(str);
  }

  if (subpath != 0 && subpath.equals("r1")) {
    last_message_time = millis();  
    lcd.setCursor(0, 1);
    lcd.print(str);
  }
  
  if (subpath != 0 && subpath.equals("r2")) {
    last_message_time = millis();
    lcd.setCursor(0, 2);
    lcd.print(str);
  }

  if (subpath != 0 && subpath.equals("r3")) {
    last_message_time = millis();
    lcd.setCursor(0, 3);
    lcd.print(str);
  }

  if (subpath != 0 && subpath.equals("clear")) {
    last_message_time = millis();
    lcd.clear();
  }

  if (subpath != 0 && subpath.equals("beep")) {
    last_message_time = millis();
    beeps = 4;
  }  
 
}

void reconnect() {
  // Loop until we're reconnected
  
  while (!client.connected()) {
    // Create a random client ID
    String clientId = "ESP8266Client-";
    clientId += String(random(0xffff), HEX);
        
    Serial.printf("Attempting MQTT connection to %s:%d from my ip\n", mqtt_server, mqtt_port);
    Serial.println(WiFi.localIP());
    lcd.setCursor(0, 0);
    lcd.print("Connecting MQTT:");
    lcd.setCursor(0, 1);
    lcd.print("                ");
    lcd.setCursor(0, 1);    
    lcd.print(mqtt_server);
    /*
    lcd.print("as client:      ");
    lcd.setCursor(0, 3);
    lcd.print("                ");
    lcd.setCursor(0, 3);
    lcd.print(clientId); 
    */
    // Attempt to connect
    if (client.connect(clientId.c_str())) {
      Serial.println("connected");
     lcd.setCursor(0, 0);
     lcd.print("Connected to:   ");
     
      // Once connected, publish an announcement...
      client.publish("nest/new_displays", path.c_str());
      // ... and resubscribe
      client.subscribe(path.c_str());
      Serial.println("Subscribed to " + path);
    } else {
      Serial.print("failed, rc=");
      Serial.print(client.state());
      Serial.println(" try again in 5 seconds");
      lcd.setCursor(0, 0);
      lcd.print("failed          ");
      lcd.setCursor(0, 1);
      lcd.print("                ");
      lcd.setCursor(0, 1);
      lcd.print(client.state()); 
          
      // Wait 5 seconds before retrying
      delay(5000);
    }
  }
}


void setup() {
  Serial.begin(115200);
  Serial.setDebugOutput(true);
  delay(10);
  Serial.println("Setup( )");
  pinMode(BUZZER_PIN, OUTPUT);
  byte count = 0;
 
  Wire.begin();
  for (byte i = 1; i < 120; i++)
  {
    Wire.beginTransmission (i);
    if (Wire.endTransmission () == 0)
      {
      Serial.print ("Found address: ");
      Serial.print (i, DEC);
      Serial.print (" (0x");
      Serial.print (i, HEX);
      Serial.println (")");
      count++;
      delay (1);  // maybe unneeded?
      } // end of good response
  } // end of for loop
  Serial.println ("Done.");
  Serial.print ("Found ");
  Serial.print (count, DEC);
  Serial.println (" device(s).");

 
  lcd.init();   // initializing the LCD
  lcd.createChar(1, up_arrow);
  lcd.createChar(2, down_arrow);
  lcd.backlight(); // Enable or Turn On the backlight 
  lcd.setCursor(0, 0);
  lcd.print("SSID           \0");
  lcd.setCursor(0, 1);
  lcd.print("MAC:           \1");
  WiFi.persistent(false);
  WiFi.setOutputPower(0);
  WiFi.begin(ssid, password);
  delay(1000);
  lcd.setCursor(0, 0);
  lcd.print(ssid);
  lcd.setCursor(0, 1);
  lcd.print(WiFi.macAddress());
  Serial.println("LCD started");

  byte i = 0;
  while (WiFi.status() != WL_CONNECTED) {
    delay(1000);
    i++;
    Serial.printf("Trying to connect to %s with pass %s\n", ssid, password);
    lcd.setCursor(15, 0);
    lcd.print(rolling[rolling_pos++]);
    if (rolling_pos >= sizeof(rolling)-2) {
      rolling_pos = 0;
    }
    if (i > 10) {
      Serial.println("Resetting wifi");
      WiFi.mode(WIFI_OFF);   // this is a temporary line, to be removed after SDK update to 1.5.4
      WiFi.mode(WIFI_STA);
      WiFi.begin(ssid, password);
      i = 0;
      Serial.println("wifi reset done.");

    }

  }
  lcd.setCursor(15, 0);
  lcd.print(" ");

  Serial.print(F("My IP is: "));
  Serial.println(WiFi.localIP());
  lcd.setCursor(0,0);
  lcd.print("Connected. IP:  ");
  lcd.setCursor(0,1);
  lcd.print("                ");
  lcd.setCursor(0,1);
  lcd.print(WiFi.localIP());
  path += WiFi.macAddress() + "/#";  
  randomSeed(micros());
  client.setServer(mqtt_server, mqtt_port);
  client.setCallback(callback);

  last_message_time = millis();
}

// the loop function runs over and over again forever
void loop() {
  if (!client.connected()) {
    reconnect();
  }
  client.loop();

  if (beeps > 0) {
    beeps--;
    digitalWrite(BUZZER_PIN, HIGH);
    delay(100);
    digitalWrite(BUZZER_PIN, LOW);
    client.loop();
    delay(100);
  }

  if (last_message_time + 120 * 1000 < millis()) {
    lcd.setCursor(0, 0);
    lcd.print("no data         ");
    lcd.setCursor(0, 1);
    lcd.print("                ");
  }
}

