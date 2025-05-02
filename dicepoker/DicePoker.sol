// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title DicePoker
/// @notice Two-phase, two-player dice “poker”: 5 dice each, bet, reveal 3 dice, bet again, reveal last 2, highest sum wins
contract DicePoker {
    enum GameState {
        Joining,
        // first betting round
        Player1Bet1,
        Player2BetOrCall1,
        Player1RaiseOrCall1,
        Player2RaiseOrCall1,
        // first-3-dice reveal
        Player1RollFirst,
        Player2RollFirst,
        // second betting round
        Player1Bet2,
        Player2BetOrCall2,
        Player1RaiseOrCall2,
        Player2RaiseOrCall2,
        // final-2-dice reveal
        Player1RollLast,
        Player2RollLast,
        // finish
        DetermineWinner,
        Tie,
        GameEnded
    }

    // --- EVENTS ---
    event PlayerJoined(address indexed player);
    event BetPlaced(address indexed player, uint256 amount);
    event DiceRolled(address indexed player, uint8[5] dice);
    event WinnerDeclared(address indexed winner, uint256 payout);

    // --- STATE ---
    GameState public currentState;
    address[2] public players;
    uint256 public pot;
    uint256 public currentBet;
    uint256[2] public bets;           // reused across both betting rounds
    uint8[5][2] public playerDice;
    bool[2] public hasRolledFirst;
    bool[2] public hasRolledLast;
    bool public gameStarted;
    uint8 public roundNumber;         // 0 after first-3 reveal, 1 after last-2 reveal
    address public currentBettor;
    address public winner;
    uint256 public gameEndedTimestamp;
    address private owner;

    uint8 private constant FIRST_ROLL_OFFSET = uint8(GameState.Player1RollFirst);
    uint8 private constant LAST_ROLL_OFFSET  = uint8(GameState.Player1RollLast);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        currentState = GameState.Joining;
    }

    /// @notice Join the game as player 1 or 2
    function joinGame() external {
        require(currentState == GameState.Joining, "Cannot join");
        require(players[0] != msg.sender && players[1] != msg.sender, "Already joined");
        require(players[0] == address(0) || players[1] == address(0), "Game full");

        uint8 idx = players[0] == address(0) ? 0 : 1;
        players[idx] = msg.sender;
        emit PlayerJoined(msg.sender);

        // once both joined, start first betting
        if (players[0] != address(0) && players[1] != address(0)) {
            currentState   = GameState.Player1Bet1;
            gameStarted    = true;
            currentBettor  = players[0];
        }
    }

    /// @notice Place or raise a bet (round 1 or round 2)
    function placeBet() external payable {
        require(gameStarted, "Not started");
        uint8 idx = msg.sender == players[0] ? 0 : 1;

        if (currentState <= GameState.Player2RaiseOrCall1) {
            _place(idx, msg.value);
            _advanceBet1();
        } else if (currentState >= GameState.Player1Bet2 && currentState <= GameState.Player2RaiseOrCall2) {
            _place(idx, msg.value);
            _advanceBet2();
        } else {
            revert("Not in betting phase");
        }
    }

    function _place(uint8 idx, uint256 amount) internal {
        require(amount > 0, "Bet must be > 0");
        // first wager of the round resets currentBet
        if (currentState == GameState.Player1Bet1 || currentState == GameState.Player1Bet2) {
            currentBet = amount;
        } else {
            require(bets[idx] + amount >= currentBet, "Underbet");
            if (bets[idx] + amount > currentBet) {
                currentBet = bets[idx] + amount;
            }
        }
        bets[idx] += amount;
        pot += amount;
        emit BetPlaced(msg.sender, amount);
    }

    function _advanceBet1() internal {
        if (currentState == GameState.Player1Bet1) {
            currentState  = GameState.Player2BetOrCall1;
            currentBettor = players[1];
        } else if (currentState == GameState.Player2BetOrCall1) {
            currentState  = GameState.Player1RaiseOrCall1;
            currentBettor = players[0];
        } else if (currentState == GameState.Player1RaiseOrCall1) {
            currentState  = GameState.Player2RaiseOrCall1;
            currentBettor = players[1];
        } else {
            // both matched ⇒ reveal first 3 dice
            currentState  = GameState.Player1RollFirst;
            currentBettor = players[0];
            delete bets;
            currentBet    = 0;
        }
    }

    function _advanceBet2() internal {
        if (currentState == GameState.Player1Bet2) {
            currentState  = GameState.Player2BetOrCall2;
            currentBettor = players[1];
        } else if (currentState == GameState.Player2BetOrCall2) {
            currentState  = GameState.Player1RaiseOrCall2;
            currentBettor = players[0];
        } else if (currentState == GameState.Player1RaiseOrCall2) {
            currentState  = GameState.Player2RaiseOrCall2;
            currentBettor = players[1];
        } else {
            // both matched ⇒ reveal last 2 dice
            currentState  = GameState.Player1RollLast;
            currentBettor = players[0];
        }
    }

    /// @notice Call the current bet (round 1 or 2)
    function call() external payable {
        require(gameStarted, "Not started");
        uint8 idx = msg.sender == players[0] ? 0 : 1;
        uint256 toCall = currentBet - bets[idx];
        require(toCall > 0, "Nothing to call");
        require(msg.value == toCall, "Incorrect call amount");

        bets[idx] += msg.value;
        pot += msg.value;
        emit BetPlaced(msg.sender, msg.value);

        // advance as if they matched
        if (currentState <= GameState.Player2RaiseOrCall1) {
            _advanceBet1();
        } else if (currentState <= GameState.Player2RaiseOrCall2) {
            _advanceBet2();
        } else {
            revert("Not in call phase");
        }
    }

    /// @notice Fold and concede the pot (round 1 or 2)
    function fold() external {
        require(gameStarted, "Not started");
        uint8 idx = msg.sender == players[0] ? 0 : 1;
        require(
            currentState <= GameState.Player2RaiseOrCall1 ||
            (currentState >= GameState.Player1Bet2 && currentState <= GameState.Player2RaiseOrCall2),
            "Cannot fold now"
        );
        winner = players[1 - idx];
        _finalize();
    }

    /// @notice Reveal dice: first 3 in first roll, last 2 in second roll
    function rollDice() external {
        require(gameStarted, "Not started");
        uint8 idx   = msg.sender == players[0] ? 0 : 1;
        uint8 phase = uint8(currentState);

        //  --- first-3 dice phase ---
        if (phase == FIRST_ROLL_OFFSET + idx) {
            require(!hasRolledFirst[idx], "Already revealed first 3");
            for (uint8 i = 0; i < 3; i++) {
                uint256 rnd = uint256(
                    keccak256(abi.encodePacked(block.timestamp, msg.sender, i, roundNumber))
                );
                playerDice[idx][i] = uint8(rnd % 6) + 1;
            }
            hasRolledFirst[idx] = true;
            emit DiceRolled(msg.sender, playerDice[idx]);
            roundNumber++;

            if (idx == 0) {
                currentState  = GameState.Player2RollFirst;
                currentBettor = players[1];
            } else {
                currentState  = GameState.Player1Bet2;
                currentBettor = players[0];
            }

        //  --- last-2 dice phase ---
        } else if (phase == LAST_ROLL_OFFSET + idx) {
            require(!hasRolledLast[idx], "Already revealed last 2");
            for (uint8 i = 3; i < 5; i++) {
                uint256 rnd = uint256(
                    keccak256(abi.encodePacked(block.timestamp, msg.sender, i, roundNumber))
                );
                playerDice[idx][i] = uint8(rnd % 6) + 1;
            }
            hasRolledLast[idx] = true;
            emit DiceRolled(msg.sender, playerDice[idx]);
            roundNumber++;

            if (idx == 0) {
                currentState  = GameState.Player2RollLast;
                currentBettor = players[1];
            } else {
                // once both have revealed all 5, decide
                currentState = GameState.DetermineWinner;
                _determineWinner();
            }

        } else {
            revert("Not in reveal phase");
        }
    }

    /// @notice Compare sums of all 5 dice and finalize the pot
    function _determineWinner() internal {
        uint16 sum0; uint16 sum1;
        for (uint8 i = 0; i < 5; i++) {
            sum0 += playerDice[0][i];
            sum1 += playerDice[1][i];
        }
        if (sum0 > sum1) {
            winner = players[0];
        } else if (sum1 > sum0) {
            winner = players[1];
        } else {
            winner = address(0); // tie
        }
        _finalize();
    }

    /// @notice Internal payout and enter the “ended” state
    function _finalize() internal {
        if (winner != address(0)) {
            payable(winner).transfer(pot);
        } else {
            // split on tie
            payable(players[0]).transfer(pot/2);
            payable(players[1]).transfer(pot/2);
        }
        emit WinnerDeclared(winner, pot);

        gameEndedTimestamp = block.timestamp;
        currentState       = GameState.GameEnded;
    }

    /// @notice Once 5 seconds have passed after a win, anyone can call to reset
    function resetIfExpired() external {
        require(currentState == GameState.GameEnded, "Game not ended");
        require(block.timestamp >= gameEndedTimestamp + 5, "Wait 5s");
        _reset();
    }

    function _reset() internal {
        delete players;
        delete bets;
        delete playerDice;
        delete hasRolledFirst;
        delete hasRolledLast;
        pot               = 0;
        currentBet        = 0;
        roundNumber       = 0;
        winner            = address(0);
        gameStarted       = false;
        currentState      = GameState.Joining;
    }

    receive() external payable {}
}
