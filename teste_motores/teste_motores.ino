//Tutorial: https://lastminuteengineers.com/l298n-dc-stepper-driver-arduino-tutorial/

//Pinos IN servem para controlar a direção do motor, pinos EN a velocidade (recebem sinal de PWM)
//Motor A
#define ENA 18
#define IN1 13
#define IN2 14

//Motor B
#define ENB 19
#define IN3 26
#define IN4 25

#define MODE_BUTTON 4

struct ButtonState {
  const int pin;              
  int lastReadingState;     // para saber o estado anterior (debounce)
  unsigned long lastTimePressed; // para o temporizador do debounce
  bool triggered;
};

ButtonState button = {
  .pin = MODE_BUTTON, 
  .lastReadingState = HIGH, //PULLUP
  .lastTimePressed = 0,
  .triggered = false
};

const long DEBOUNCE_DELAY_MS = 50; 

//Função para debounce do botão
bool checkStablePress(ButtonState& btn) {
  int leitura = digitalRead(btn.pin);

  if (leitura != btn.lastReadingState) {
    btn.lastTimePressed = millis();
    btn.lastReadingState = leitura;
  }

  if ((millis() - btn.lastTimePressed) > DEBOUNCE_DELAY_MS && leitura == LOW && !btn.triggered) {
    btn.triggered = true;  // novo campo na struct
    return true;
  }

  if (leitura == HIGH) btn.triggered = false; // reseta ao soltar
  return false;
}

//Velocidades iniciais dos motores
const char velMotorA = 100; 
const char velMotorB = 100;

void runForward(){
  //Faz os dois motores girarem para frente
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
  digitalWrite(IN3, HIGH);
  digitalWrite(IN4, LOW);
  return;
}

void runBackwards(){
  //Faz os dois motores girarem para trás
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
  digitalWrite(IN3, LOW);
  digitalWrite(IN4, HIGH);
  return;
}

void turnLeft(){
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
  digitalWrite(IN3, LOW);
  digitalWrite(IN4, HIGH);
  return;
}

void turnRight(){
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
  digitalWrite(IN3, HIGH);
  digitalWrite(IN4, LOW);
  return;
}

void motorStop(){
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
  digitalWrite(IN3, LOW);
  digitalWrite(IN4, LOW);
  return;
}


String readSerial(){
  if (Serial.available() > 0) {
    // Lê o conteúdo digitado no monitor serial até o caracter de quebra de linha (após enter)
    String command = Serial.readStringUntil('\n');
    command.trim(); // Remove any accidental spaces or hidden newline character
    return command;
  }
  return(""); //Se não receber nada
}


enum MotorState{
  IDLE,
  RUN_FORWARD,
  RUN_BACKWARDS,
  TURN_RIGHT,
  TURN_LEFT,
  STOPPING
};

MotorState motorState;

void motor_fsm(){

  switch(motorState){

    case IDLE:
      return;

    case RUN_FORWARD:
      runForward();
      return;

    case RUN_BACKWARDS:
      runBackwards();
      return;

    case TURN_RIGHT:
      turnRight();
      return;

    case TURN_LEFT:
      turnLeft();
      return;
    
    case STOPPING:
      motorStop();
      motorState = IDLE;
      return;  
  }
}


void setup() {
  Serial.begin(115200);
  pinMode(ENA, OUTPUT); //Controle de velocidade motor A
  pinMode(ENB, OUTPUT); //Controle de velocidade motor B
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);
  pinMode(IN3, OUTPUT);
  pinMode(IN4, OUTPUT);

  //Inicia com dois motores desligados e com velocidade padrão
  //Seta as velocidades dos motores
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
  digitalWrite(IN3, LOW);
  digitalWrite(IN4, LOW);
  analogWrite(ENA, velMotorA);
  analogWrite(ENB, velMotorB);

  motorState = IDLE; //Começa em zero

  Serial.println("Motor inicializado. Digite 'F' no serial para alterar função.");
  Serial.print("Modo do botão: ");
  Serial.println(motorState);
  Serial.println("////////////////////////////////////////////////////////////////////////////////////////");
  //Serial.println("'1' - ANDAR PARA FRENTE\n'2' - ANDAR PARA TRÁS\n'3' - VIRAR PARA A DIREITA\n'4' - VIRAR PARA A ESQUERDA\n'5' - PARAR");
}

void loop() {
  //Incrementa o modo (0-5) quando o botão é apertado (de 5 para 0 a passagem é na própria FSM automaticamente)
  String instruction = readSerial();
  if (instruction != ""){Serial.println(instruction);}
  if (instruction == "F"){
   // Converte para int, soma 1 e transforma de volta para MotorState
    motorState = static_cast<MotorState>(static_cast<int>(motorState) + 1);
    Serial.print("Modo alterado para: ");
    Serial.println(motorState);
  }
  /*
  String command = readSerial(); //A cada início de loop checa para ver se há comandos no serial
  int selection = command.toInt();
  */
  motor_fsm();
}
