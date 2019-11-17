#!/bin/bash


NAME=$1
GREETING="Hi there"
HAT_TIP="*tip of the hat*"
HEAD_SHAKE="*slow head shake*"

if [[ "$NAME" = "Dave" ]]; then
	echo $GREETING
elif [[ "$NAME" = "Steve" ]]; then
	echo $HAT_TIP
else
	echo $HEAD_SHAKE
fi
#################################################################################
NUM_REQUIRED_ARGS=2

# Do we have at least two arguments, -lt - less
if [[ $# -lt NUM_REQUIRED_ARGS ]]; then
	echo "Not enough arguments. Call this script with
	./{$0} <name> <number>"
fi

echo "hi." || echo "this won't happen."
$(ls nonexistentfile) || echo "this happens if the first thing fails"
echo $(pwd) && echo "this ALSO happens!"

# Strings
str1="a"
str2="b"

# Equality (= and !=) (ASCII comparisson)
if [[ "$str1" = "str2" ]]; then
	echo "${str1} is equal to ${str2}!"
fi

if [[ "$str1" != "$str2" ]]; then
	echo "${str1} is not equal to ${str2}!"
fi

# Null (-n) or Zero length (-z)
notnully="this is somthing (not nothing)"
nully=""

if [[ -n "$notnully" ]]; then
	echo "This is not at all nully"
fi

if [[ -z "$nully" ]]; then
	echo "nully/zerooo (length)"
fi

# Integers
int1=1
int2=1

# equal, not equal
if [[ $int1 -eq $int2 ]]; then
	echo "${int1} is equal to ${int2}."
fi
if [[ $int1 -ne $int2 ]]; then
	echo "${int1} is NOT equal to ${int2}."
fi

# equal then, less than +equal
# -gt -lt -le
if [[ $int1 -gt $int2 ]]; then
	echo "${int1} is equal to ${int2}."
fi
if [[ $int1 -le $int2 ]]; then
	echo "${int1} is equal to ${int2}."
fi

# string comparison operators can be used with double parentheses
if (( $int1 == $int2 )); then
	echo "${int1} is equal to ${int2}."
fi
#########################################################################

