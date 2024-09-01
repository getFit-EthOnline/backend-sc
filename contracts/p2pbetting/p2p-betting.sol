// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract P2pBetting {
    address public admin;
    bool public matchEnded;
    bool public resultSet;
    string public winningOption;

    struct BettingOption {
        string name;
        uint256 totalBets;
        mapping(address => uint256) bets;
    }

    BettingOption public optionA;
    BettingOption public optionB;

    IERC20 public usdcToken;

    constructor(address _usdcTokenAddress, string memory playerA, string memory playerB) {
        admin = msg.sender;
        usdcToken = IERC20(_usdcTokenAddress);
        
        optionA.name = playerA;
        optionB.name = playerB;
    }
    
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    modifier matchNotEnded() {
        require(!matchEnded, "Match already ended");
        _;
    }
    
    function updatePlayerName(string memory oldName, string memory newName) external onlyAdmin matchNotEnded {
        require(keccak256(bytes(oldName)) == keccak256(bytes(optionA.name)) || keccak256(bytes(oldName)) == keccak256(bytes(optionB.name)), "Invalid player name");
        
        if (keccak256(bytes(oldName)) == keccak256(bytes(optionA.name))) {
            optionA.name = newName;
        } else if (keccak256(bytes(oldName)) == keccak256(bytes(optionB.name))) {
            optionB.name = newName;
        }
    }
    
    function placeBet(string memory playerName, uint256 _amount) external matchNotEnded {
        require(_amount > 0, "Bet amount must be greater than zero");
        require(keccak256(bytes(playerName)) == keccak256(bytes(optionA.name)) || keccak256(bytes(playerName)) == keccak256(bytes(optionB.name)), "Invalid betting option name");

        usdcToken.transferFrom(msg.sender, address(this), _amount);

        if (keccak256(bytes(playerName)) == keccak256(bytes(optionA.name))) {
            optionA.bets[msg.sender] += _amount;
            optionA.totalBets += _amount;
        } else if (keccak256(bytes(playerName)) == keccak256(bytes(optionB.name))) {
            optionB.bets[msg.sender] += _amount;
            optionB.totalBets += _amount;
        }
    }

    function endMatch() external onlyAdmin matchNotEnded {
        matchEnded = true;
    }
    
    function setMatchResult(string memory _winningOptionName) external onlyAdmin matchNotEnded {
        require(!resultSet, "Result already set");
        require(keccak256(bytes(_winningOptionName)) == keccak256(bytes(optionA.name)) || keccak256(bytes(_winningOptionName)) == keccak256(bytes(optionB.name)), "Invalid winning option name");

        winningOption = _winningOptionName;
        resultSet = true;
    }
    
    function withdrawWinnings() external matchNotEnded {
        require(resultSet, "Result has not been set yet");
        uint256 winnings;

        if (keccak256(bytes(winningOption)) == keccak256(bytes(optionA.name))) {
            require(optionA.bets[msg.sender] > 0, "No bets placed on the winning option");
            winnings = calculateWinnings(optionA.bets[msg.sender], optionA.totalBets, optionB.totalBets);
            optionA.bets[msg.sender] = 0;
        } else if (keccak256(bytes(winningOption)) == keccak256(bytes(optionB.name))) {
            require(optionB.bets[msg.sender] > 0, "No bets placed on the winning option");
            winnings = calculateWinnings(optionB.bets[msg.sender], optionB.totalBets, optionA.totalBets);
            optionB.bets[msg.sender] = 0;
        }
        
        usdcToken.transfer(msg.sender, winnings);
    }
    
    function calculateWinnings(uint256 userBet, uint256 totalWinnerBets, uint256 totalLoserBets) internal pure returns (uint256) {
        return (userBet * totalLoserBets) / totalWinnerBets;
    }
    
    function getContractBalance() external view returns (uint256) {
        return usdcToken.balanceOf(address(this));
    }
}
