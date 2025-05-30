// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IntegrationBase} from './IntegrationBase.sol';
import {StdStorage, stdStorage} from 'forge-std/StdStorage.sol';
import {IOpUSDCBridgeAdapter} from 'interfaces/IOpUSDCBridgeAdapter.sol';

contract dummyImplementation {
  address public minter;

  function configureMinter(address _minter) external {
    minter = _minter;
  }
}

contract Integration_Bridging is IntegrationBase {
  using stdStorage for StdStorage;

  string internal constant _NAME = 'OpEURCBridgeAdapter';
  string internal constant _VERSION = '1.0.0';

  function setUp() public override {
    super.setUp();

    _mintSupplyOnL2(optimism, OP_ALIASED_L1_MESSENGER, _amount);
  }

  /**
   * @notice Test the bridging process from L2 -> L1
   */
  function test_bridgeFromL2() public {
    vm.selectFork(optimism);

    assertEq(bridgedUSDC.balanceOf(_user), _amount);
    assertEq(bridgedUSDC.balanceOf(address(l2Adapter)), 0);

    vm.startPrank(_user);
    bridgedUSDC.approve(address(l2Adapter), _amount);
    l2Adapter.sendMessage(_user, _amount, _MIN_GAS_LIMIT);
    vm.stopPrank();

    assertEq(bridgedUSDC.balanceOf(_user), 0);
    assertEq(bridgedUSDC.balanceOf(address(l2Adapter)), 0);

    vm.selectFork(mainnet);
    uint256 _userBalanceBefore = MAINNET_USDC.balanceOf(_user);
    _relayL2ToL1Message(
      address(l2Adapter),
      address(l1Adapter),
      _ZERO_VALUE,
      _MIN_GAS_LIMIT,
      abi.encodeWithSignature('receiveMessage(address,address,uint256)', _user, _user, _amount)
    );

    assertEq(MAINNET_USDC.balanceOf(_user), _userBalanceBefore + _amount);
    assertEq(MAINNET_USDC.balanceOf(address(l1Adapter)), 0);
  }

  /**
   * @notice Test the bridging process from L2 -> L1 with a different target
   */
  function test_bridgeFromL2DifferentTarget() public {
    vm.selectFork(optimism);

    address _l1Target = makeAddr('l1Target');

    // Mint to increment total supply of bridgedUSDC and balance of _user
    vm.prank(address(l2Adapter));
    bridgedUSDC.mint(_user, _amount);

    vm.startPrank(_user);
    bridgedUSDC.approve(address(l2Adapter), _amount);
    l2Adapter.sendMessage(_l1Target, _amount, _MIN_GAS_LIMIT);
    vm.stopPrank();

    assertEq(bridgedUSDC.balanceOf(_user), _amount);
    assertEq(bridgedUSDC.balanceOf(address(l2Adapter)), 0);

    vm.selectFork(mainnet);
    uint256 _userBalanceBefore = MAINNET_USDC.balanceOf(_user);

    _relayL2ToL1Message(
      address(l2Adapter),
      address(l1Adapter),
      _ZERO_VALUE,
      _MIN_GAS_LIMIT,
      abi.encodeWithSignature('receiveMessage(address,address,uint256)', _l1Target, _user, _amount)
    );

    assertEq(MAINNET_USDC.balanceOf(_l1Target), _userBalanceBefore + _amount);
    assertEq(MAINNET_USDC.balanceOf(address(l1Adapter)), 0);
  }

  /**
   * @notice Test bridging with a user who is blacklisted on L1
   */
  function test_bridgingWithBlacklistedUser() public {
    vm.selectFork(mainnet);
    vm.prank(MAINNET_USDC.blacklister());
    MAINNET_USDC.blacklist(_user);

    vm.selectFork(optimism);
    // Mint to increment total supply of bridgedUSDC and balance of _user
    vm.prank(address(l2Adapter));
    bridgedUSDC.mint(_user, _amount);

    uint256 _userBalanceBefore = bridgedUSDC.balanceOf(_user);
    vm.startPrank(_user);
    bridgedUSDC.approve(address(l2Adapter), _amount);
    l2Adapter.sendMessage(_user, _amount, _MIN_GAS_LIMIT);
    vm.stopPrank();

    assertEq(bridgedUSDC.balanceOf(_user), _userBalanceBefore - _amount);
    assertEq(bridgedUSDC.balanceOf(address(l2Adapter)), 0);

    vm.selectFork(mainnet);
    _relayL2ToL1Message(
      address(l2Adapter),
      address(l1Adapter),
      _ZERO_VALUE,
      _MIN_GAS_LIMIT,
      abi.encodeWithSignature('receiveMessage(address,address,uint256)', _user, _user, _amount)
    );

    assertEq(MAINNET_USDC.balanceOf(_user), 0);
    assertEq(MAINNET_USDC.balanceOf(address(l1Adapter)), _amount);
    assertEq(l1Adapter.lockedFundsDetails(_user, _user), _amount);
  }

  /**
   * @notice Test bridging with signature
   */
  function test_bridgeFromL2WithSig() public {
    (address _signerAd, uint256 _signerPk) = makeAddrAndKey('signer');
    vm.selectFork(optimism);

    // Mint to increment total supply of bridgedUSDC and balance of _user
    vm.prank(address(l2Adapter));
    bridgedUSDC.mint(_signerAd, _amount);

    vm.prank(_signerAd);
    bridgedUSDC.approve(address(l2Adapter), _amount);
    uint256 _deadline = block.timestamp + 1 days;
    bytes memory _signature = _generateSignature(
      _NAME,
      _VERSION,
      _signerAd,
      _amount,
      _deadline,
      _MIN_GAS_LIMIT,
      _USER_NONCE,
      _signerAd,
      _signerPk,
      address(l2Adapter)
    );

    // Different address can execute the message
    vm.prank(_user);
    l2Adapter.sendMessage(_signerAd, _signerAd, _amount, _signature, _USER_NONCE, _deadline, _MIN_GAS_LIMIT);

    assertEq(bridgedUSDC.balanceOf(_signerAd), 0);
    assertEq(bridgedUSDC.balanceOf(_user), _amount);
    assertEq(bridgedUSDC.balanceOf(address(l2Adapter)), 0);

    vm.selectFork(mainnet);
    uint256 _userBalanceBefore = MAINNET_USDC.balanceOf(_user);

    _relayL2ToL1Message(
      address(l2Adapter),
      address(l1Adapter),
      _ZERO_VALUE,
      _MIN_GAS_LIMIT,
      abi.encodeWithSignature('receiveMessage(address,address,uint256)', _signerAd, _signerAd, _amount)
    );

    assertEq(MAINNET_USDC.balanceOf(_signerAd), _userBalanceBefore + _amount);
    assertEq(MAINNET_USDC.balanceOf(address(l1Adapter)), 0);
  }

  /**
   * @notice Test signature message reverts with a signature that was canceled by disabling the nonce
   */
  function test_bridgeFromL2WithCanceledSignature() public {
    (address _signerAd, uint256 _signerPk) = makeAddrAndKey('signer');
    vm.selectFork(optimism);

    // Mint to increment total supply of bridgedUSDC and balance of _user
    vm.startPrank(address(l2Adapter));
    bridgedUSDC.mint(_signerAd, _amount);
    bridgedUSDC.mint(_user, _amount);
    vm.stopPrank();

    // Give allowance to the adapter
    vm.prank(_signerAd);
    bridgedUSDC.approve(address(l2Adapter), _amount);

    // Changing to `to` param to _user but we call it with _signerAd
    uint256 _deadline = block.timestamp + 1 days;
    bytes memory _signature = _generateSignature(
      _NAME, _VERSION, _user, _amount, _deadline, _MIN_GAS_LIMIT, _USER_NONCE, _signerAd, _signerPk, address(l2Adapter)
    );

    // Cancel the signature
    vm.prank(_signerAd);
    l2Adapter.cancelSignature(_USER_NONCE);

    // Different address will execute the message, and it should revert because the nonce is disabled
    vm.startPrank(_user);
    vm.expectRevert(IOpUSDCBridgeAdapter.IOpUSDCBridgeAdapter_InvalidNonce.selector);
    l2Adapter.sendMessage(_signerAd, _signerAd, _amount, _signature, _USER_NONCE, _deadline, _MIN_GAS_LIMIT);
  }

  /**
   * @notice Test signature message reverts with incorrect signature
   */
  function test_bridgeFromL2WithIncorrectSignature() public {
    (address _signerAd, uint256 _signerPk) = makeAddrAndKey('signer');
    vm.selectFork(optimism);

    // Mint to increment total supply of bridgedUSDC and balance of _user
    vm.startPrank(address(l2Adapter));
    bridgedUSDC.mint(_signerAd, _amount);
    bridgedUSDC.mint(_user, _amount);
    vm.stopPrank();

    // Give allowance to the adapter
    vm.prank(_signerAd);
    bridgedUSDC.approve(address(l2Adapter), _amount);

    // Changing to `to` param to _user but we call it with _signerAd
    uint256 _deadline = block.timestamp + 1 days;
    bytes memory _signature = _generateSignature(
      _NAME, _VERSION, _user, _amount, _deadline, _MIN_GAS_LIMIT, _USER_NONCE, _signerAd, _signerPk, address(l2Adapter)
    );

    // Different address can execute the message
    vm.startPrank(_user);
    ///  NOTE: Didn't us `vm.expectRevert(IOpUSDCBridgeAdapter.IOpUSDCBridgeAdapter_InvalidSignature.selector)` because
    /// it reverts with that error, but then the test fails because of a foundry issue with the error message
    /// `contract signer does not exist`, which is not true.
    vm.expectRevert();
    l2Adapter.sendMessage(_signerAd, _signerAd, _amount, _signature, _USER_NONCE, _deadline, _MIN_GAS_LIMIT);
    vm.stopPrank();
  }
}

contract Integration_PermissionedUsdcFlows is IntegrationBase {
  address internal _notOwner = makeAddr('notOwner');
  address internal _newImplementation;

  function setUp() public override {
    super.setUp();

    _newImplementation = address(new dummyImplementation());

    // Select the Optimism fork
    vm.selectFork(optimism);
  }

  /**
   * @notice Test `upgradeTo` USDC function on L2
   */
  function test_UpgradeTo() public {
    // Setup necessary data
    bytes memory _calldata = abi.encodeWithSignature('upgradeTo(address)', _newImplementation);

    // Use L2OpUSDCBridgeAdapter owner to call `upgradeTo` function through the adapter
    vm.startPrank(_owner);

    // Call `upgradeTo` function
    l2Adapter.callUsdcTransaction(_calldata);

    // Check that the USDC implementation has been upgraded
    assertEq(bridgedUSDC.implementation(), _newImplementation);
  }

  /**
   * @notice Test `upgradeToAndCall` USDC function on L2
   */
  function test_UpgradeToAndCall() public {
    // Setup necessary data
    bytes memory _functionToCall = abi.encodeWithSignature('configureMinter(address)', _notOwner);
    bytes memory _calldata =
      abi.encodeWithSignature('upgradeToAndCall(address,bytes)', _newImplementation, _functionToCall);

    // Use L2OpUSDCBridgeAdapter owner to call `upgradeToAndCall` function through the adapter
    vm.prank(_owner);
    // Call `upgradeToAndCall` function
    l2Adapter.callUsdcTransaction(_calldata);

    // Check that the USDC implementation has been upgraded
    assertEq(bridgedUSDC.implementation(), _newImplementation);
    assertEq(dummyImplementation(address(bridgedUSDC)).minter(), _notOwner);
  }

  /**
   * @notice Test `updatePauser` USDC function on L2
   */
  function test_UpdatePauser() public {
    // Setup necessary data
    bytes memory _calldata = abi.encodeWithSignature('updatePauser(address)', _notOwner);

    // Use L2OpUSDCBridgeAdapter owner to call `updatePauser` function through the adapter
    vm.startPrank(_owner);

    // Call `updatePauser` function
    l2Adapter.callUsdcTransaction(_calldata);

    // Call pauser function to get the pauser
    (, bytes memory _data) = address(bridgedUSDC).call(abi.encodeWithSignature('pauser()'));

    //Get pauser from _data
    address _pauser = address(uint160(uint256(bytes32(_data))));

    // Check that the USDC pauser has been updated
    assertEq(_pauser, _notOwner);
  }

  /**
   * @notice Test `updateBlacklister` USDC function on L2
   */
  function test_UpdateBlacklister() public {
    // Setup necessary data
    bytes memory _calldata = abi.encodeWithSignature('updateBlacklister(address)', _notOwner);

    // Use L2OpUSDCBridgeAdapter owner to call `updateBlacklister` function through the adapter
    vm.startPrank(_owner);

    // Call `updateBlacklister` function
    l2Adapter.callUsdcTransaction(_calldata);

    //Call blacklister function to get the blacklister
    (, bytes memory _data) = address(bridgedUSDC).call(abi.encodeWithSignature('blacklister()'));

    //Get blacklister from _data
    address _blacklister = address(uint160(uint256(bytes32(_data))));

    // Check that the USDC blacklister has been updated
    assertEq(_blacklister, _notOwner);
  }

  /**
   * @notice Test `updateRescuer` USDC function on L2
   */
  function test_UpdateRescuer() public {
    // Setup necessary data
    bytes memory _calldata = abi.encodeWithSignature('updateRescuer(address)', _notOwner);

    // Use L2OpUSDCBridgeAdapter owner to call `updateRescuer` function through the adapter
    vm.startPrank(_owner);

    // Call `updateRescuer` function
    l2Adapter.callUsdcTransaction(_calldata);

    //Call rescuer function to get the rescuer
    (, bytes memory _data) = address(bridgedUSDC).call(abi.encodeWithSignature('rescuer()'));

    //Get rescuer from _data
    address _rescuer = address(uint160(uint256(bytes32(_data))));

    // Check that the USDC rescuer has been updated
    assertEq(_rescuer, _notOwner);
  }
}
