const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Wallet", function () {
  it("Should return this once it's tested successfully!", async function () {
    const Wallet = await ethers.getContractFactory("Wallet");
    const wallet = await Wallet.deploy("Hello, world!");
    await wallet.deployed();

    const Investment = await wallet.setInvestmentName("Soldex");
    await Investment.wait();

    const TotalShares = await wallet.setTotalShares("25000");
    await TotalShares.wait();    

    const InvestmentName = await wallet.getInvestmentName();
    console.log("Your Investment name is:",InvestmentName);

    const TotalSharesCount = await wallet.totalShares();
    console.log("Total shares of your investments:",TotalSharesCount);

  });
});
