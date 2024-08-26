const axios = require('axios');
const fs = require('fs');
const argv = require('yargs').argv;
const path = require('path');
const mime = require('mime-types');

// Configuration
const zenodo_url = 'https://zenodo.org';

// Function to create a new record
async function createRecord(recordName, recordDescription, recordCreator, accessToken) {
    const url = `${zenodo_url}/api/deposit/depositions`;
    const config = {
        method: 'post',
        url: url,
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${accessToken}`,
        },
        data: JSON.stringify({
            "metadata": {
                "title": recordName,
                "upload_type": "dataset",
                "description": recordDescription,
                "creators": [
                    {
                        "name": recordCreator
                    }
                ]
            }
        })
    };

    try {
        const response = await axios(config);
        return response.data;
    } catch (error) {
        console.error(error);
    }
}

// Function to upload a file
async function uploadFile(bucketURL, filePath, accessToken) {

    const fileName = path.basename(filePath);

    let contentType = mime.contentType(fileName)
      ? mime.contentType(fileName)
      : 'text/plain';

    // Read file as a stream
    const stream = fs.createReadStream(filePath);

    let contentLength = fs.statSync(filePath).size.toString();



    let url = `${bucketURL}/${fileName}`;

    let params = { 'access_token': accessToken }

    const headers = {
      Authorization: `token  ${accessToken}`,
      'Content-Type': "application/octet-stream",
      'Content-Length': contentLength,
    };

    const requestConfig = {
        method: 'put',
        url,
        headers,
        maxContentLength: Infinity,
        maxBodyLength: Infinity,
        data: stream,
    };

    const response = await axios(requestConfig)
      .then(function (response) {
        return response.data;
      })
      .catch(function (error) {
        try {
          core.error(
            `Error with zenodo upload: ${error.response.data.message}`,
          );
        } catch (e) {
          //do nothing
        }
        return 'ERROR';
      });
    return(response)
}

async function publishRecord(DepositionId, accessToken) {
    const url = `${zenodo_url}/api/deposit/depositions/${DepositionId}/actions/publish?access_token=${accessToken}`;
    const response = await axios.post(url);
    if (response.status === 202) {
        const final_url = `${zenodo_url}/records/${DepositionId}`;
        console.log(final_url);
    } else {
        console.log(error.response.data);
        process.exit(1);
    }
}

// Main execution
async function main() {
    if (!argv.recordName ||!argv.fileToUpload ||!argv.accessToken) {
        console.log('Usage: node uploadToZenodo.js --recordName <recordName> --fileToUpload <fileToUpload>');
        process.exit(1);
    }

    const record = await createRecord(argv.recordName, argv.recordDescription, argv.recordCreator, argv.accessToken);
    if (record !== 'ERROR') {
        const bucketUrl = record.links.bucket;
        const uploadedFile = await uploadFile(bucketUrl, argv.fileToUpload, argv.accessToken);
        if (uploadedFile) {
            await publishRecord(record.id, argv.accessToken)
        }
    }
}

main();
		