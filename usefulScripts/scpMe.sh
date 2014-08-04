 #!/bin/bash
PARAM_ERR1="param one not passed"  # Not enough params passed to function.
PARAM_ERR2="param two not passed"  # Not enough params passed to function.
PARAM_ERR3="param three not passed"  # Not enough params passed to function.
unix() { 
   { 
if [ "$1" == s ]; then
   scp "$2" user@unix4.csc.calpoly.edu:~
elif [ "$1" == sr ]; then
      scp -r "$2" user@unix4.csc.calpoly.edu:~
elif [ "$1" == r ]; then
	 scp user@unix3.csc.calpoly.edu:/home/user/"$2"   "$2"
elif [ "$1" == rr ]; then
	 scp -r user@unix4.csc.calpoly.edu:/home/user/"$2"   "$2"
else
  echo invalid send option
fi
   }
}
arch() {  
   {
if [ "$1" == s ]; then
    scp -P 6969 "$2" user@99.99.99.99:~
elif [ "$1" == sr ]; then
    scp -r -P 6969 "$2" user@99.99.99.99:~
elif [ "$1" == r ]; then
   scp -P 6969 user@99.99.99.99:~/"$2" "$2"
elif [ "$1" == rr ]; then
   scp -r -P 6969 user@99.99.99.99:~/"$2" "$2" 
else
  echo invalid send option 
fi
   }
}

media() {  
   {
if [ "$1" == s ]; then
    echo sending $2 to user@00.000.000.000:~
    scp "$2" user@00.000.000.000:~
elif [ "$1" == sr ]; then
    echo recursively sending $2 to user@00.000.000.000:~
    scp -r "$2" user@00.000.000.000:~
elif [ "$1" == r ]; then
   echo receiving $2 from user@00.000.000.000:
   scp  user@00.000.000.000:~/"$2" "$2" 
elif [ "$1" == rr ]; then
   echo recursively receiving $2 from user@00.000.000.000:
   scp -r user@00.000.000.000:~/"$2" "$2"
else
  echo invalid send option 
fi
   }
}
myweb() {  
   {
if [ "$1" == s ]; then
    scp -P 73 "$2" user@64.233.160.0:~
elif [ "$1" == sr ]; then
    scp -r -P 73 "$2" user@64.233.160.0:~
elif [ "$1" == r ]; then
   scp -P 73 user@64.233.160.0:~/"$2" "$2" 
elif [ "$1" == rr ]; then
   scp -r -P 73 user@64.233.160.0:~/"$2" "$2" 
else
  echo invalid send option
fi
   }
}
doRealStuff(){
if [ "$2" == unix4 ]; then
   unix $1 $3
elif [ "$2" == arch ]; then
   arch $1 $3
elif [ "$2" == media ]; then
   media $1 $3
elif [ "$2" == myweb ]; then
   myweb $1 $3
else
   echo you are trying to send/receive to/from a server that doesnt exist
fi

}
if [ -z "$1" ]
then
   echo $PARAM_ERR1
   echo Would you like to send \(s\), send recursively \(sr\), receive \(r\), or recursively receive \(rr\)?
   read x
else
   x=$1
#   1=$x
fi
if [ -z "$2" ]
then
   echo $PARAM_ERR2
   echo from/to where? \(unix4,arch,media,myweb\)
   read from
else
   from=$2
fi
if [ -z "$3" ]
then
   echo $PARAM_ERR3
   echo name of file or directory \(including absolute path\) 
   read name
else
   name=$3
#  3=$name
fi
doRealStuff $x $from $name
