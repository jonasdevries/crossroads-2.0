export default {
    testEnvironment: 'node',
    transform: {},
    setupFiles: ['dotenv/config'],
    "collectCoverage": true,
    "coverageReporters": ["html", "text-summary"],
    "coverageDirectory": "coverage",
    "reporters": [
        "default",
        ["jest-html-reporters", { "publicPath": "./test-report", "filename": "index.html", "expand": true }]
    ]
};