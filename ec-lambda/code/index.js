const AWS = require("aws-sdk");
const [, instanceId] = process.env.instanceArn.split("/");
const InstanceIds = [instanceId];

exports.start = (event, context, callback) => {
  const ec2 = new AWS.EC2({ region: event.instanceRegion });
  return ec2
    .startInstances({ InstanceIds })
    .promise()
    .then(() => `Successfully started`)
    .catch((err) => console.log(err));
};

exports.stop = (event, context, callback) => {
  const ec2 = new AWS.EC2({ region: event.instanceRegion });
  return ec2
    .stopInstances({ InstanceIds })
    .promise()
    .then(() => `Successfully stopped`)
    .catch((err) => console.log(err));
};
