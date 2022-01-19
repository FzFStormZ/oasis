#include "types.h"
#include "metrics.h"
#include "callbacks.h"
#include "hashmap.h"
#include "malloc.h"

bool is_scanning = 0;

void CONN_INIT_CALLBACK(btlejuice)(metrics_t * metrics) {
  if(!is_scanning) {
    /*stop_scan();
    start_scan();*/
    is_scanning = 1;
  }
}

void CONN_RX_CALLBACK(btlejuice)(metrics_t * metrics) {

  if(is_scanning && metrics->current_connection->rx_counter > 75) {
    //stop_scan();
    is_scanning = 0;
  }
}

void SCAN_CALLBACK(btlejuice)(metrics_t * metrics) {
  if(is_scanning && metrics->current_packet->valid && get_adv_packet_type() == ADV_IND) {
    //log(metrics->remote_device->address,6);
    bool same = 1;
    uint8_t i = 0;

    while(same && i < 6) {
      same = metrics->remote_device->address[i] == metrics->local_device->address[i];
      i++;
    }

    if(same) {
      is_scanning = 0;
      log(metrics->remote_device->address,6);
      //stop_scan();
    }

  }
}
