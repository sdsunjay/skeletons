echo "nvm install 18.12.0"
nvm install 18.12.0
echo "node"
node
echo "npm install aws-cdk-lib"
npm install aws-cdk-lib
echo "curl \"https://awscli.amazonaws.com/AWSCLIV2.pkg\" -o \"AWSCLIV2.pkg\""
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
echo "sudo installer -pkg AWSCLIV2.pkg -target /"
sudo installer -pkg AWSCLIV2.pkg -target /
echo "which aws"
which aws
echo "aws --version"
aws --version
PS3="Enter a number: "

select language in typescript javascript python csharp go
do
    echo "Selected language: $language"
    echo "Selected number: $REPLY"
    break
done
echo "npm -g install $language"
npm -g install $language
echo "npm install -g aws-cdk"
npm install -g aws-cdk
echo "Get access key ID and secret access key from IAM AWS console"
echo "https://us-east-1.console.aws.amazon.com/iamv2/home"
read -p "Press enter to run 'aws configure'"
aws configure # get access key ID and secret access key from IAM AWS console
echo "mkdir static-website-cdk"
mkdir static-website-cdk
echo "cd static-website-cdk"
cd static-website-cdk
echo "cdk init app --language $language"
cdk init app --language $language
echo ls
ls
echo "npm run build"
npm run build
echo "vim lib/static-website-cdk-stack.ts"
vim lib/static-website-cdk-stack.ts
