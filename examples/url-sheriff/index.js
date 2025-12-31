import express from 'express';
import fetch from 'node-fetch';
import { default as URLSheriff } from 'url-sheriff';

const app = express();
const port = 3000;

// Initialize sheriff
const sheriff = new URLSheriff();

app.get('/', async (req, res) => {
    const url = req.query.url;

    if (!url) {
        return res.status(400).send('Missing "url" query parameter');
    }

    try {
        // 1. Validate URL with url-sheriff (Time-of-Check)
        // detailed check including IP resolution
        console.log("Validating URL: " + url);
        await sheriff.isSafeURL(url);
        console.log("URL is safe");

        // Might be needed to bypass DNS caching on some cases. E.g., with CloudFlare's DNS.
        // console.log("Waiting 10 seconds...");
        // await new Promise((resolve) => setTimeout(resolve, 10000));
        // console.log("Good morning!");

        // 2. Fetch the URL (Time-of-Use)
        // potential race condition / different resolution
        console.log("Fetching URL: " + url);
        const response = await fetch(url);
        const data = await response.text();

        res.send(data);
    } catch (error) {
        console.error('Error:', error.message);
        res.status(500).send('Request failed or blocked: ' + error.message);
    }
});

app.listen(port, () => {
    console.log(`Vulnerable app listening on port ${port}`);
});

const internalApp = express();
const internalPort = 80;

internalApp.get('/', (req, res) => {
    res.send('internal');
});

internalApp.listen(internalPort, () => {
    console.log(`Internal service listening on port ${internalPort}`);
});
