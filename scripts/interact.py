from utils import patch_parser,conf_parser
from interface import openocd,internalblue
import sys

if len(sys.argv) < 3:
    print("Usage: "+sys.argv[0]+" <target> <command>")
    print("Commands: read <symbol>")
    print("Commands: read <address>")
    print("Commands: read <address> <size>")
    print("Commands: monitor <symbol>")
    print("Commands: monitor <address>")
    print("Commands: monitor <address> <size>")
    print("Commands: log")
    print("Commands: start-scan")
    print("Commands: stop-scan")

    exit(1)

target = sys.argv[1]
command = sys.argv[2].lower()

def getInterface():
    interfaceType = conf_parser.getTargetInterface(target)
    if "INTERNALBLUE" in interfaceType:
        interface = internalblue.InternalblueInterface(target)
    else:
        interface = openocd.OpenocdInterface(target)
    return interface

def read(address,value):
    interface = getInterface()
    interface.connect()
    print(interface.read(address,size).hex())
    interface.disconnect()

def monitor(address,value):
    interface = getInterface()
    interface.connect()
    value = b""
    printedValue = b""
    try:
        while True:
            value = interface.read(address,size)
            if value != printedValue:
                printedValue = value
                print(printedValue.hex())
    except KeyboardInterrupt:
        interface.disconnect()

if command == "log":
    interface = getInterface()
    interface.connect()
    try:
        for log in interface.log():
            print(log.hex())
    except KeyboardInterrupt:
        interface.disconnect()
        exit(0)
elif command == "read" or command == "monitor":
    if len(sys.argv) < 4:
        print("Please provide a symbol or an address to read.")
        exit(2)
    information = sys.argv[3]
    address = None
    size = None
    if information.startswith("0x"):
        address = int(information,16)
        if len(sys.argv) == 5:
            try:
                size = int(sys.argv[4])
            except:
                print("Please provide a valid size.")
                exit(4)
    else:
        patches = patch_parser.getMapping(target)
        if patches is None:
            print("Mapping file not found.")
            exit(3)
        for patch in patches:
            if patch["patch_name"] == information:
                address = patch["patch_address"]
                size = len(patch["patch_content"])
                break
        if address is None and size is None:
            print("Symbol not found.")
            exit(5)
    if address is not None and size is not None:
        if command == "read":
            read(address,size)
        elif command == "monitor":
            monitor(address,size)
elif command == "start-scan":
    interface = getInterface()
    interface.connect()
    if interface.sendHciCommand(0x200b,bytes.fromhex("00002000200000")): # set scan parameters
        print("Set Scan Parameters OK")
    else:
        print("Error during Set Scan Parameters")

    if interface.sendHciCommand(0x200c,bytes.fromhex("0101")): # set scan enable
        print("Set Scan Enable OK")
    else:
        print("Error during Set Scan Enable")

    interface.disconnect()
elif command == "stop-scan":
    interface = getInterface()
    interface.connect()

    if interface.sendHciCommand(0x200c,bytes.fromhex("0001")): # set scan enable
        print("Set Scan Enable OK")
    else:
        print("Error during Set Scan Enable")
    interface.disconnect()
