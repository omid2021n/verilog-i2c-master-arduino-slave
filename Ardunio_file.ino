#include <Wire.h>

#define SLAVE_ADDRESS 0x08

volatile byte receivedValue = 0;
volatile bool newDataFlag = false;

void setup() {
  Serial.begin(115200);
  while (!Serial);

  Wire.begin(SLAVE_ADDRESS);
  Wire.onReceive(receiveEvent);

  Serial.println("Arduino I2C Slave Receiver Ready...");
}

void loop() {
  if (newDataFlag) {
    noInterrupts();
    byte val = receivedValue;
    newDataFlag = false;
    interrupts();

    Serial.print("Counter Value Received: ");
    Serial.println(val);
  }
}

// Runs in TWI ISR context — keep this as short as physically possible
void receiveEvent(int howMany) {
  if (Wire.available()) {
    receivedValue = Wire.read();
    newDataFlag = true;
  }
  // Drain anything extra without processing, so the bus isn't held up
  while (Wire.available()) {
    Wire.read();
  }
}
