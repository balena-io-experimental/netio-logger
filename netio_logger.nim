# Prints network transfer in bytes through a provided interface, over a provided
# time interval.
# Expects METRICS_REQUEST and READING_INTERVAL_SEC environment variables.
# Prints 0,0 if any error.

import asyncdispatch, os, parseutils, strformat, strutils, tables
import psutil

# byte counters for interface
let counters = {"rx_bytes": 0, "tx_bytes": 0}.newTable
# last rx/tx values for interface
let lastValues = {"rx_bytes": 0, "tx_bytes": 0}.newTable
var ifname: string
var readingInterval: int
const detailSeparator = "/"

proc collect(iface : string, readings: TableRef) =
    ## Collects readings for RX and TX bytes for the interface.
    if iface == "*":
        # print the first one
        for netio in per_nic_net_io_counters().values:
            readings["rx_bytes"] = netio.bytes_recv
            readings["tx_bytes"] = netio.bytes_sent
            break
    else:
        try:
            let netio = per_nic_net_io_counters()[iface]
            readings["rx_bytes"] = netio.bytes_recv
            readings["tx_bytes"] = netio.bytes_sent
        except:
            discard

proc collectCb(fd: AsyncFD) : bool {.gcsafe.} =
    ## Timer callback to collect readings and update counters.
    let ifnameLocal = ifname
    let readings = {"rx_bytes": 0, "tx_bytes": 0}.newTable

    collect(ifnameLocal, readings)
    for k, v in readings.mpairs:
        counters[k] = counters[k] + v - lastValues[k]
        lastValues[k] = v
    echo &"{counters[\"rx_bytes\"]},{counters[\"tx_bytes\"]}"
    # must return false for a periodic timer
    return false

proc initVars() =
    # Initialize interface name and reading interval from environment, and counters.
    # Typical request: "networkStats/iface, networkStats/rx_bytes, networkStats/tx_bytes, networkStats/(wwp1s0u1u1i4)"
    let requestStr = getEnv("METRICS_REQUEST", "networkStats/(lo)")
    echo &"Request text: {requestStr}"
    try:
        for item in split(requestStr, ','):
            let detailIndex = item.find(detailSeparator)
            let detail = item[detailIndex+1 .. ^1]
            if detail[0] == '(' and detail[^1] == ')':
                ifname = detail[1 .. ^2]
                if ifname != "*":
                    ifname = ifname & ":"
    except:
        ifname = "unknown"

    discard parseInt(getEnv("READING_INTERVAL_SEC", "10"), readingInterval)
    readingInterval *= 1000
    echo &"Reading interval: {readingInterval} ms"


initVars()

# Initialize lastValues on current readings
echo "Collecting initial readings"
let readings = {"rx_bytes": 0, "tx_bytes": 0}.newTable
collect(ifname, readings)
for k, v in readings.mpairs:
    lastValues[k] = v
echo "\nelapsedRx,elapsedTx"

addTimer(readingInterval, false, collectCb)
while hasPendingOperations():
    poll()
