# Makefile for OOOP C++ Model

CXX = g++
CXXFLAGS = -std=c++17 -Wall -Wextra -O2 -g
INCLUDES = -I./include
TARGET = ooop_sim

# Source files
SRCS = src/main.cpp \
       src/core.cpp \
       src/fetch.cpp \
       src/decode.cpp \
       src/rename.cpp \
       src/dispatch.cpp \
       src/rs.cpp \
       src/rob.cpp \
       src/prf.cpp \
       src/map_table.cpp \
       src/free_list.cpp \
       src/rob_tag_alloc.cpp \
       src/alu_fu.cpp \
       src/branch_fu.cpp \
       src/lsu_fu.cpp \
       src/icache.cpp \
       src/dmem.cpp \
       src/recovery_ctrl.cpp \
       src/types.cpp

# Object files
OBJS = $(SRCS:.cpp=.o)

# Build target
all: $(TARGET)

$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^

%.o: %.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET)

run: $(TARGET)
	./$(TARGET) ../trace/25instMem-test.txt

.PHONY: all clean run
