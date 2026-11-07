import { expect } from "chai";
import hre from "hardhat";
import fs from "fs";
import path from "path";
import { deployFixture } from "../../vendor/gmx/utils/fixture";
import { expandDecimals, decimalToFloat } from "../../vendor/gmx/utils/math";
import { handleDeposit } from "../../vendor/gmx/utils/deposit";
import { OrderType, handleOrder } from "../../vendor/gmx/utils/order";
import { updateAdlState, executeAdl } from "../../vendor/gmx/utils/adl";
import { grantRole } from "../../vendor/gmx/utils/role";
import { getAccountPositionCount, getPositionKey } from "../../vendor/gmx/utils/position";
import * as keys from "../../vendor/gmx/utils/keys";

describe("HedgePact.NativeShort",()=>{
 it("opens 100 ETH short, ADLs 40 ETH and closes the remaining 60 ETH",async()=>{
  const f=await deployFixture();const {wallet,user0}=f.accounts;
  const {roleStore,dataStore,reader,ethUsdMarket,wethPriceFeed,wnt,usdc,exchangeRouter}=f.contracts;
  await handleDeposit(f,{create:{market:ethUsdMarket,longTokenAmount:expandDecimals(1000,18),shortTokenAmount:expandDecimals(2000000,6)}});
  const cb=await (await hre.ethers.getContractFactory("MockCallbackReceiver")).deploy();await cb.deployed();
  await exchangeRouter.connect(user0).setSavedCallbackContract(ethUsdMarket.marketToken,cb.address);
  await handleOrder(f,{create:{market:ethUsdMarket,initialCollateralToken:usdc,initialCollateralDeltaAmount:expandDecimals(100000,6),sizeDeltaUsd:decimalToFloat(500000),acceptablePrice:expandDecimals(4999,12),orderType:OrderType.MarketIncrease,isLong:false}});
  const pk=getPositionKey(user0.address,ethUsdMarket.marketToken,usdc.address,false);
  const opened=await reader.getPosition(dataStore.address,pk);
  expect(opened.numbers.sizeInTokens).eq(expandDecimals(100,18));
  await dataStore.setUint(keys.maxPnlFactorKey(keys.MAX_PNL_FACTOR_FOR_ADL,ethUsdMarket.marketToken,false),decimalToFloat(10,2));
  await dataStore.setUint(keys.minPnlFactorAfterAdl(ethUsdMarket.marketToken,false),decimalToFloat(2,2));
  await grantRole(roleStore,wallet.address,"ADL_KEEPER");await wethPriceFeed.setAnswer(expandDecimals(2500,8));
  const prices={tokens:[wnt.address,usdc.address],minPrices:[expandDecimals(2500,4),expandDecimals(1,6)],maxPrices:[expandDecimals(2500,4),expandDecimals(1,6)]};
  await updateAdlState(f,{market:ethUsdMarket,isLong:false,...prices});
  const calls=await cb.called();
  await executeAdl(f,{account:user0.address,market:ethUsdMarket,collateralToken:usdc,isLong:false,sizeDeltaUsd:decimalToFloat(200000),...prices});
  const remaining=await reader.getPosition(dataStore.address,pk);
  expect(await cb.called()).gt(calls);expect(remaining.numbers.sizeInTokens).eq(expandDecimals(60,18));
  await handleOrder(f,{create:{market:ethUsdMarket,initialCollateralToken:usdc,initialCollateralDeltaAmount:0,sizeDeltaUsd:decimalToFloat(300000),acceptablePrice:expandDecimals(2501,12),orderType:OrderType.MarketDecrease,isLong:false},execute:prices});
  expect(await getAccountPositionCount(dataStore,user0.address)).eq(0);
  const globals:any[]=[];
  for(const [name,key] of Object.entries(keys)){
   if(!/^[A-Z_0-9]+$/.test(name)||typeof key!=="string"||key.length!==66)continue;
   const u=await dataStore.getUint(key);if(!u.isZero())globals.push({name,key,type:"uint256",value:u.toString()});
   const a=await dataStore.getAddress(key);if(a!==hre.ethers.constants.AddressZero)globals.push({name,key,type:"address",value:a});
   if(await dataStore.getBool(key))globals.push({name,key,type:"bool",value:true});
  }
  const roles:any[]=[];for(const role of await roleStore.getRoles(0,await roleStore.getRoleCount())){for(const member of await roleStore.getRoleMembers(role,0,await roleStore.getRoleMemberCount(role)))roles.push({role,member});}
  fs.writeFileSync(path.resolve(__dirname,"../../gmx/fixture.json"),JSON.stringify({deployments:await hre.deployments.all(),globals,roles},null,2));
  fs.writeFileSync(path.resolve(__dirname,"../../evidence/native-short.json"),JSON.stringify({status:"PASS",environment:"LOCAL_FULL_GMX_ENGINE",upstream:"a85ea3491c19c93bb4b5a002d9b358fb769b7849",openedTokens:opened.numbers.sizeInTokens.toString(),remainingAfterAdl:remaining.numbers.sizeInTokens.toString(),remainingAfterClose:"0",nativeCallbackCalls:(await cb.called()).toString(),notPublic:true},null,2));
 });
});
