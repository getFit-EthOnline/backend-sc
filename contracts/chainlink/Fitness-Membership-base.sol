// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

contract Autopay is CCIPReceiver,ReentrancyGuard, AutomationCompatibleInterface, Ownable, FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;

    LinkTokenInterface private s_linkToken;


    bytes32 public s_lastRequestId;
    bytes public s_lastResponse;
    bytes public s_lastError;
    string public lastConfirmationMsg;

    error UnexpectedRequestID(bytes32 requestId);
    // Event emitted when a message is sent to another chain.
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        address user,
        address coach,
        uint256 cost,
        uint256 interval
    );

    struct FitnessSchedule {
        address user;
        address coach;
        uint256 startTime;
        uint256 endTime;
        uint256 interval;
        uint256 cost;
        uint256 ntfnAttempts;
        bool isActive;
    }

    mapping(uint256 => FitnessSchedule) public FitnessSchedules; // Mapping from ID to FitnessSchedule details
    uint256 public nextFitnessScheduleId;

    event FitnessScheduleCreated(uint256 indexed FitnessScheduleId, address indexed user, address indexed coach, uint256 startTime, uint256 endTime, uint256 interval, uint256 cost);

    event UnexpectedRequestIDError(bytes32 indexed requestId);
    event DecodingFailed(bytes32 indexed requestId);
    event ResponseError(bytes32 indexed requestId, bytes err);
    event Response(bytes32 indexed requestId, string response, bytes err);

    // Eth Sepolia Configs
    address router = 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93;
    address routerFunctions = 0xf9B8fc078197181C841c296C876945aaa425B278;
    uint32 gasLimit = 300_000;
    uint64 subscriptionIdFunctions = 171;
    bytes32 donID = 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000;
    string source = 
        "const userAddress = args[0];"
        "const fitnessCoachAddress = args[1];"
        "const url = `https://chainlink-ntfn-service-getFit.onrender.com/send-email`;"
        "console.log(`HTTP GET Request to ${url}?userAddress=${userAddress}&fitnessCoachAddress=${fitnessCoachAddress}`);"
        "const emailRequest = Functions.makeHttpRequest({"
        "  url: url,"
        "  headers: {"
        "    'Content-Type': 'application/json',"
        "  },"
        "  timeout: 9000,"
        "  params: {"
        "    userAddress: userAddress,"
        "    fitnessCoachAddress: fitnessCoachAddress,"
        "  },"
        "});"
        "const emailResponse = await emailRequest;"
        "return Functions.encodeString(`Notified User with ${userAddress} & Coach ${fitnessCoachAddress}`);";

    

    IERC20 public paymentToken;


    constructor(address _paymentToken, address _linkTokenAddress)FunctionsClient(routerFunctions) CCIPReceiver(router) Ownable(_msgSender()) {
        paymentToken = IERC20(_paymentToken);
        s_linkToken = LinkTokenInterface(_linkTokenAddress);
    }

    /// @notice Handles the reception of cross-chain messages via CCIP.
    /// @param message The incoming message from the cross-chain transaction.
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        // Decode the message data to extract the FitnessSchedule parameters
        (address user, address coach, uint256 startTime, uint256 interval, uint256 cost) = 
            abi.decode(message.data, (address, address, uint256, uint256, uint256));
        
        uint256 endTime = startTime + interval;
        // Transfer the paymentToken amount from the address to the coach (since its already transfered from the destination chain)
        require(paymentToken.transfer(coach, cost), "Transfer failed");

        // Create a new FitnessSchedule on the destination chain
        uint256 scheduleId = nextFitnessScheduleId++;
        FitnessSchedules[scheduleId] = FitnessSchedule({
            user: user,
            coach: coach,
            startTime: startTime,
            endTime: endTime,
            interval: interval,
            cost: cost,
            ntfnAttempts: 0,
            isActive: true
        });

        emit FitnessScheduleCreated(scheduleId, user, coach, startTime, endTime, interval, cost);
    }

    /// @notice Sends a cross-chain subscription along with the FitnessSchedule details.
    /// @param _destinationChainSelector The selector for the destination chain.
    /// @param _receiver The address of the contract on the destination chain.
    /// @param user The user initiating the subscription.
    /// @param coach The coach to be assigned.
    /// @param startTime The start time of the fitness schedule.
    /// @param interval The interval of the fitness schedule.
    /// @param cost The cost of the fitness schedule.
    /// @param _amount The amount of tokens for the subscription.
    /// @return messageId The ID of the sent cross-chain message.
    function sendUsdcCrossChainSubscription(
        uint64 _destinationChainSelector,
        address _receiver,
        address user,
        address coach,
        uint256 startTime,
        uint256 interval,
        uint256 cost,
        uint256 _amount
    ) external returns (bytes32 messageId) {
        // Transfer the paymentToken amount from the user to the contract
        require(paymentToken.transferFrom(msg.sender, address(this), _amount), "Transfer failed");

        // Encode the necessary data for creating the FitnessSchedule on the destination chain
        bytes memory data = abi.encode(user, coach, startTime, interval, cost);

        // Build the CCIP message with the encoded data
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            data,
            address(paymentToken),
            _amount,
            address(s_linkToken)
        );

        // Calculate the fees for sending the cross-chain message
        uint256 fees = IRouterClient(router).getFee(_destinationChainSelector, evm2AnyMessage);
        require(fees <= s_linkToken.balanceOf(address(this)), "Not enough LINK tokens for fees");

        // Approve the router to spend the paymentToken and pay fees
        paymentToken.approve(router, _amount);
        s_linkToken.approve(router, fees);

        // Send the cross-chain message
        messageId = IRouterClient(router).ccipSend(_destinationChainSelector, evm2AnyMessage);

        // Emit the event for the cross-chain subscription
        emit MessageSent(messageId, _destinationChainSelector, _receiver, user, coach, cost, interval);

        return messageId;
    }

    /// @notice Constructs the cross-chain message for CCIP.
    /// @param _receiver The address of the contract on the destination chain.
    /// @param data The encoded data for the message (fitness schedule details).
    /// @param _token The address of the token to be transferred.
    /// @param _amount The amount of the token.
    /// @return Client.EVM2AnyMessage The CCIP message with the fitness schedule details and token.
    function _buildCCIPMessage(
        address _receiver,
        bytes memory data,
        address _token,
        uint256 _amount,
        address _feeTokenAddress
    ) private pure returns (Client.EVM2AnyMessage memory) {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({ token: _token, amount: _amount });

        return Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: data,
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({ gasLimit: 200_000 })),
            feeToken: _feeTokenAddress
        });
    }

    function fitnessSubscription(
        address user,
        address coach,
        uint256 interval,
        uint256 cost  
    ) external returns (uint256 FitnessScheduleId) {
        // Transfer the paymentToken amount from the user to the coach
        require(paymentToken.transferFrom(msg.sender, coach, cost), "Transfer failed");
        FitnessScheduleId = nextFitnessScheduleId++;
        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + interval;

        FitnessSchedules[FitnessScheduleId] = FitnessSchedule(user, coach, startTime, endTime, interval,cost, 0, true);

        emit FitnessScheduleCreated(FitnessScheduleId, user, coach, startTime, endTime, interval,cost);
    }

    function checkUpkeep(bytes calldata) view  external override returns (bool upkeepNeeded, bytes memory performData) {
        uint256[] memory dueFitnessSchedules = new uint256[](nextFitnessScheduleId);
        uint256 count = 0;

        for (uint256 i = 0; i < nextFitnessScheduleId; i++) {
            FitnessSchedule memory TestFitnessSchedule = FitnessSchedules[i];
            if (TestFitnessSchedule.endTime <= block.timestamp && TestFitnessSchedule.isActive) {
                dueFitnessSchedules[count] = i;
                count++;
            }
        }

        if (count > 0) {
            bytes memory data = abi.encode(dueFitnessSchedules);
            return (true, data);
        }

        return (false, "");
    }

    function performUpkeep(bytes calldata performData) external override {
        uint256[] memory expiredTokenIds = abi.decode(performData, (uint256[]));

        for (uint256 i = 0; i < expiredTokenIds.length; i++) {
            uint256 tokenId = expiredTokenIds[i];
            FitnessSchedule storage TestFitnessSchedule = FitnessSchedules[tokenId];

            if (paymentToken.balanceOf(TestFitnessSchedule.user) >= TestFitnessSchedule.cost && paymentToken.allowance(TestFitnessSchedule.user, address(this)) >= TestFitnessSchedule.cost) {
                require(paymentToken.transferFrom(TestFitnessSchedule.user, TestFitnessSchedule.coach, TestFitnessSchedule.cost));
                TestFitnessSchedule.endTime = block.timestamp + TestFitnessSchedule.interval;
            } else {
                TestFitnessSchedule.ntfnAttempts++;
                if (TestFitnessSchedule.ntfnAttempts >= 2) {
                    TestFitnessSchedule.isActive = false;
                }

                string[] memory args = new string[](2);
                args[0] = toAsciiString(TestFitnessSchedule.user);
                args[1] = toAsciiString(TestFitnessSchedule.coach);

                sendRequest(subscriptionIdFunctions, args);
            }
        }
    }


    function sendRequest(uint64 subscriptionId, string[] memory args) public returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);
        if (args.length > 0) req.setArgs(args);
        s_lastRequestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donID);
        return s_lastRequestId;
    }

    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        if (s_lastRequestId != requestId) {
            emit Response(requestId, string(response), err);
            return;
        }
        s_lastResponse = response;
        s_lastError = err;
        lastConfirmationMsg = string(response);
        emit Response(requestId, lastConfirmationMsg, s_lastError);
    }

  
    function updatePaymentToken(address newPaymentTokenAddress) public onlyOwner {
        require(newPaymentTokenAddress != address(0), "Invalid address");
        paymentToken = IERC20(newPaymentTokenAddress);
    }

    function toAsciiString(address x) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint(uint160(x)) / (2**(8*(19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2*i] = char(hi);
            s[2*i+1] = char(lo);
        }
        return string(s);
    }

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }

    function uintToString(uint v) internal pure returns (string memory) {
        if (v == 0) {
            return "0";
        }
        uint j = v;
        uint length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint k = length;
        while (v != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(v - v / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            v /= 10;
        }
        return string(bstr);
    }
}