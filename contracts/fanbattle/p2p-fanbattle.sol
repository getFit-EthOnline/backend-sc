// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FanBattle {

    address public admin;
    mapping(string => address) public teamTokens; // Maps team names to their token contracts
    mapping(address => string) public userTeams; // Maps user addresses to their team names
    mapping(string => address[]) public teamMembers;  // Store multiple user address for each team
    mapping(address => uint256) public userScores; // Scores or achievements for each user
    mapping(uint256 => address) public rankings; // Mapping of rank positions to user addresses

    uint256 public startTime;
    uint256 public endTime;
    bool public isEventActive;
    bool public winnersDeclared;

    mapping(uint256 => uint256) public prizes; // USDC prizes for positions
    address public usdcToken;
    address public fanToken;

    event TeamAdded(string teamName, address token);
    event JoinedTeam(address user, string team);
    event ScoreUpdated(address user, uint256 score);
    event PrizeSet(uint256 position, uint256 amount);
    event RankingUpdated(uint256 position, address user);
    event RewardsClaimed(address user, uint256 usdcAmount);

    constructor(address _usdcToken) {
        admin = msg.sender;
        usdcToken = _usdcToken;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this.");
        _;
    }

    function addTeam(string memory teamName, address tokenAddress) external onlyAdmin {
        teamTokens[teamName] = tokenAddress;
        emit TeamAdded(teamName, tokenAddress);
    }

    function setPrizeAmounts(uint256[] memory positions, uint256[] memory amounts) external onlyAdmin {
        require(!winnersDeclared, "Cannot set prize after winners declared");
        require(positions.length == amounts.length, "Positions and amounts length mismatch");

        for (uint256 i = 0; i < positions.length; i++) {
            prizes[positions[i]] = amounts[i];
            emit PrizeSet(positions[i], amounts[i]);
        }
    }

    function setEventTime(uint256 _start, uint256 _end) external onlyAdmin {
        startTime = _start;
        endTime = _end;
        isEventActive = true;
        winnersDeclared = false;
    }

    function joinTeam(string memory teamName) external {
        require(isEventActive, "Event not active");
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Event not running");
        require(teamTokens[teamName] != address(0), "Team does not exist");

        IERC20 teamToken = IERC20(teamTokens[teamName]);
        uint256 balance = teamToken.balanceOf(msg.sender);
        require(balance > 0, "You need the team's token to join");

        userTeams[msg.sender] = teamName;
        teamMembers[teamName].push(msg.sender);
        emit JoinedTeam(msg.sender, teamName);
    }

    function updateRankingsAndScores(uint256[] memory positions, address[] memory users, uint256[] calldata scores) external onlyAdmin {
        require(positions.length == users.length && users.length == scores.length, "Input arrays length mismatch");

        for (uint256 i = 0; i < positions.length; i++) {
            rankings[positions[i]] = users[i];
            userScores[users[i]] = scores[i];
            emit RankingUpdated(positions[i], users[i]);
            emit ScoreUpdated(users[i], scores[i]);
        }
        winnersDeclared = true;
    }

    function claimReward(uint256 position) external {
        require(winnersDeclared, "Winners not declared yet");
        require(rankings[position] == msg.sender, "Not eligible for this position reward");

        IERC20(usdcToken).transfer(msg.sender, prizes[position]);
        emit RewardsClaimed(msg.sender, prizes[position]);
    }
}
