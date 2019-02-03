#!/bin/bash

ERL_NODE=${1:-1}

iex --cookie 1234567890 --name node$ERL_NODE@127.0.0.1 -S mix
