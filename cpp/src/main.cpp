#include "core.h"
#include <iostream>
#include <string>
#include <iomanip>

void printUsage(const char* prog) {
    std::cerr << "Usage: " << prog << " <inst_mem_file.txt> [max_cycles]" << std::endl;
    std::cerr << "  inst_mem_file.txt: Instruction memory file (byte format)" << std::endl;
    std::cerr << "  max_cycles: Maximum cycles to run (default: 20000)" << std::endl;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        printUsage(argv[0]);
        return 1;
    }
    
    std::string inst_file = argv[1];
    uint64_t max_cycles = 20000;
    
    if (argc >= 3) {
        max_cycles = std::stoull(argv[2]);
    }
    
    std::cout << "============================================================" << std::endl;
    std::cout << "OOOP C++ Model" << std::endl;
    std::cout << "============================================================" << std::endl;
    std::cout << "Instruction file: " << inst_file << std::endl;
    std::cout << "Max cycles: " << max_cycles << std::endl;
    std::cout << std::endl;
    
    Core core;
    
    if (!core.loadProgram(inst_file)) {
        std::cerr << "ERROR: Failed to load program" << std::endl;
        return 1;
    }
    
    core.reset();
    core.run(max_cycles);
    
    std::cout << std::endl;
    std::cout << "============================================================" << std::endl;
    std::cout << "FINAL RESULTS @ cycle=" << core.getCycleCount()
              << " commits=" << core.getCommitCount() << std::endl;
    
    // Print a0 (x10) and a1 (x11)
    uint32_t a0 = core.getArchRegValue(10);
    uint32_t a1 = core.getArchRegValue(11);
    
    std::cout << "a0 (x10) = 0x" << std::hex << std::setw(8) << std::setfill('0')
              << a0 << " (" << std::dec << static_cast<int32_t>(a0) << ")" << std::endl;
    std::cout << "a1 (x11) = 0x" << std::hex << std::setw(8) << std::setfill('0')
              << a1 << " (" << std::dec << static_cast<int32_t>(a1) << ")" << std::endl;
    std::cout << "============================================================" << std::endl;
    
    return 0;
}
