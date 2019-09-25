#!/bin/bash

# TODO Remove verbose once verified in stage. All starting with T
printenv | grep '^T' | tr '\0' '\n'
