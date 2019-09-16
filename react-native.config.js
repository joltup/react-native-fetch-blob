module.exports = {
  dependency: {
    hooks: {
      prelink: "node ./node_modules/rn-fetch-blob/scripts/prelink.js"
    }
  }
};
