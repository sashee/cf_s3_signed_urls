## S3 Signed URLs through CloudFront

### Prerequisites

* npm
* terraform

### Deploy

* ```cd src && npm ci```
* ```terraform apply```
* wait patiently

### Use

To get a signed URL:

```
terraform output signer_url
```

To get the HTML through the signed URL:

```
curl -s $(curl -s $(terraform output signer_url))
```

### Destroy

```
terraform destroy
```
