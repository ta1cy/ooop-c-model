#include "icache.h"
#include <fstream>
#include <iostream>
#include <string>

ICache::ICache() : rdata_q(0), rvalid_q(false) {
    mem.fill(0x00000013); // NOP (addi x0, x0, 0)
}

bool ICache::loadProgram(const std::string& filename) {
    std::ifstream file(filename);
    if (!file.is_open()) {
        std::cerr << "[icache] ERROR: Could not open file: " << filename << std::endl;
        return false;
    }
    
    std::vector<uint8_t> bytes;
    std::string line;
    
    while (std::getline(file, line)) {
        // Skip empty lines and comments
        if (line.empty() || line[0] == '#' || line[0] == '/') {
            continue;
        }
        
        // Trim whitespace
        size_t start = line.find_first_not_of(" \t\r\n");
        if (start == std::string::npos) continue;
        
        line = line.substr(start);
        
        // Parse hex byte
        try {
            unsigned int byte_val = std::stoul(line, nullptr, 16);
            bytes.push_back(static_cast<uint8_t>(byte_val));
        } catch (...) {
            // Skip invalid lines
            continue;
        }
    }
    
    // Pack bytes into words (little-endian)
    for (size_t i = 0; i + 3 < bytes.size() && i / 4 < DEPTH_WORDS; i += 4) {
        uint32_t word = bytes[i] |
                       (bytes[i+1] << 8) |
                       (bytes[i+2] << 16) |
                       (bytes[i+3] << 24);
        mem[i / 4] = word;
    }
    
    std::cout << "[icache] Loaded " << bytes.size() << " bytes ("
              << (bytes.size() / 4) << " words)" << std::endl;
    
    return true;
}

void ICache::tick(bool en, uint32_t addr) {
    if (en) {
        uint32_t word_idx = addr >> 2;
        if (word_idx < DEPTH_WORDS) {
            rdata_q = mem[word_idx];
            rvalid_q = true;
        } else {
            rdata_q = 0x00000013; // NOP
            rvalid_q = true;
        }
    } else {
        rvalid_q = false;
    }
}
