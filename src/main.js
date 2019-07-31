const AWS = require("aws-sdk");
const tk = require("timekeeper");

const s3 = new AWS.S3({
	signatureVersion: "v4",
});

const getTruncatedTime = () => {
	const currentTime = new Date();
	const d = new Date(currentTime);

	d.setMinutes(Math.floor(d.getMinutes() / 30) * 30);
	d.setSeconds(0);
	d.setMilliseconds(0);

	return d;
};

module.exports.handler = async (event, context, callback) => {
	const params = {Bucket: process.env.BUCKET, Key: "index.html", Expires: 3600};

	const url = tk.withFreeze(getTruncatedTime(), () => {
		return s3.getSignedUrl( "getObject", params);
	});

	const CFurl = url.replace(new RegExp("(.*)://.*?/(.*)"), `$1://${process.env.DISTRIBUTION_DOMAIN}/$2`);
	const response = {
		statusCode: 200,
		body: CFurl,
	};
	callback(null, response);
};
