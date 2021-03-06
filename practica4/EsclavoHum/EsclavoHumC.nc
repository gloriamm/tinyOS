#include "EsclavoHum.h"

module EsclavoHumC {
	uses interface Boot;
	uses interface Leds;
	uses interface CC2420Packet;
	uses interface Packet;
	uses interface AMPacket;
	uses interface AMSend;
	uses interface Receive;
	uses interface SplitControl as AMControl;
	uses interface Read<uint16_t> as Humidity;
	uses interface Timer<TMilli> as Timer0;
}
implementation {
	uint16_t rssi;			   	// Almacena la medida de RSSI
	uint16_t humedad;			// Almacena la medida de humedad
	message_t pkt;			   	// Espacio para el pkt a tx
	bool busy = FALSE;		 	// Flag para comprobar el estado de la radio

	// Obtiene el valor RSSI del paquete recibido
	uint16_t getRssi(message_t *msg){
		return (uint16_t) call CC2420Packet.getRssi(msg);
	}

	// Mide la humedad. Almacena el valor en medida. Si hay error almacena 0xFFFF
	event void Humidity.readDone(error_t result, uint16_t val) {
		if(result == SUCCESS) {
			humedad = -0.0000028*val*val+0.0405*val-4;
		}
		else {
			humedad = 0xFFFF;
		}
	}

	// Se ejecuta al alimentar t-mote. Arranca la radio
	event void Boot.booted() {
		call AMControl.start();
	}

	// Arranca la radio si la primera vez hubo algún error
	event void AMControl.startDone(error_t err) {
		if (err != SUCCESS) {
			call AMControl.start();
		}
	}

	event void AMControl.stopDone(error_t err) {
	}

	// Después de esperar, toca enviar. Cuando acaba el temporizador...
	event void Timer0.fired() {
		// Si no está ocupado forma y envía el mensaje
		if (!busy) {
			// Reserva memoria para el paquete
			EsclavoMsg* pktesclavo_tx = (EsclavoMsg*)(call Packet.getPayload(&pkt, sizeof(EsclavoMsg)));

			// Reserva errónea
			if (pktesclavo_tx == NULL) {
				return 0;
			}

			// Forma el paquete a tx
			pktesclavo_tx->ID_esclavo = ESCLAVO_HUM_ID;  	// Campo 1: ID esclavo
			pktesclavo_tx->medidaRssi = rssi;      			// Campo 2: Medida RSSI
			pktesclavo_tx->tipo = HUMEDAD;					// Campo 3: Tipo de medida (1 = Temperatura    2 = Humedad    3 = Luminosidad)
			pktesclavo_tx->medida = humedad;    	 		// Campo 4: Valor de medida

			// Envía
			if (call AMSend.send(MAESTRO_ID, &pkt, sizeof(EsclavoMsg)) == SUCCESS) {
				//						|-> Destino = Maestro
				busy = TRUE;	// Ocupado
				call Leds.led0Off();   // Led 0 Off
				call Leds.led1On();    // Led 1 ON cuando envío mi paquete
			}
		}
	}

	// Comprueba la tx del pkt y marca como libre si ha terminado
	event void AMSend.sendDone(message_t* msg, error_t err) {
		if (&pkt == msg) {
			busy = FALSE;	// Libre
		}
	}

	// Comprueba la rx de un pkt
	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
		MaestroMsg* pktmaestro_rx = (MaestroMsg*)payload;	// Extrae el payload

		// Si el paquete tiene la longitud correcta y es de mi maestro
		if (len == sizeof(MaestroMsg) && pktmaestro_rx->ID_maestro == MAESTRO_ID) {
			call Leds.led0On();    // Led 0 ON cuando me llega el paquete del Jefe
			call Leds.led1Off();   // Led 1 OFF

			rssi = getRssi(msg);		// Calcula el RSSI
			call Humidity.read();		// Mide la humedad

			// Comprueba el slot que se le ha asignado
			// 1º slot => Transmitir
			if (pktmaestro_rx->first == ESCLAVO_HUM_ID) {
				// No espera nada
				call Timer0.startPeriodic(0);
			}
			// 2º slot => Esperar 1 slot y Transmitir
			else if (pktmaestro_rx->second == ESCLAVO_HUM_ID) {
				// Espera 1 slot = Periodo/nº slots
				call Timer0.startPeriodic(TIMER_PERIOD_MILLI/SLOTS);
			}
			// 3º slot => Esperar 2 slots y Transmitir
			else if (pktmaestro_rx->third == ESCLAVO_HUM_ID) {
				// Espera 2 slots = 2*Periodo/nº slots
				call Timer0.startPeriodic(2*TIMER_PERIOD_MILLI/SLOTS);
			}
			// En cualquiera de los casos cuando expira el temporizador dirige a "event void Timer0.fired()
		}

		return msg;
	}
}
