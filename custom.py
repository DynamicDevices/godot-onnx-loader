# Loaded by godot-cpp/SConstruct (customs). Quiets known godot-cpp header noise.
# Our addon sources use strict -Werror in SConstruct (separate env clone).


def configure(env):
    env.Append(CCFLAGS=["-Wno-unused-parameter"])
    env.Append(CXXFLAGS=["-Wno-unused-parameter"])
