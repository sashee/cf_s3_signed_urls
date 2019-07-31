## S3 Signed URLs through CloudFront

* ```cd src && npm ci```
* ```terraform apply```
* wait patiently

To get a signed URL:

```
terraform output signer_url
```

To get the HTML through the signed URL:

```
curl -s $(curl -s $(terraform output signer_url))
```
