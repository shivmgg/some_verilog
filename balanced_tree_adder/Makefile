# build and run simulation
# 

# tools
VERILOG:=iverilog
SIMULATOR:=vvp

SRCS := balanced_tree_adder.v balanced_adder_test.v  balanced_adder_tb.v

.PHONY : all

all: balanced_tree


# build simulation
balanced_tree : $(SRCS)
	$(VERILOG) -o $@  $(SRCS)	


# run simulation
.PHONY : runsim
runsim:
	$(SIMULATOR) balanced_tree


# cleanup
.PHONY : clean
clean:
	$(RM) *.o

# delete all built files
.PHONY : realclean
realclean:
	$(RM) balanced_tree

