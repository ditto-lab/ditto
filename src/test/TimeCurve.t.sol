pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../TimeCurve.sol";

contract TimeCurveTest is Test {

    uint256[255] outputs = [0, 285105, 553439, 806399, 1046704, 1276498, 1497396, 1710632, 1917170, 2117779, 2313085, 2503604, 2689772, 2871956, 3050474, 3225600, 3397573, 3566605, 3732883, 3896575, 4057830, 4216784, 4373558, 4528266, 4681007, 4831874, 4980955, 5128327, 5274063, 5418231, 5560893, 5702109, 5841932, 5980413, 6117601, 6253541, 6388274, 6521840, 6654276, 6785619, 6915902, 7045156, 7173411, 7300696, 7427038, 7552464, 7676997, 7800661, 7923478, 8045470, 8166658, 8287061, 8406697, 8525586, 8643743, 8761186, 8877930, 8993991, 9109384, 9224122, 9338220, 9451691, 9564546, 9676800, 9788462, 9899545, 10010060, 10120018, 10229428, 10338302, 10446647, 10554475, 10661794, 10768612, 10874939, 10980782, 11086151, 11191051, 11295492, 11399480, 11503023, 11606128, 11708801, 11811049, 11912879, 12014297, 12115308, 12215919, 12316136, 12415964, 12515409, 12614476, 12713170, 12811497, 12909462, 13007069, 13104323, 13201228, 13297791, 13394014, 13489902, 13585459, 13680690, 13775599, 13870189, 13964465, 14058430, 14152088, 14245442, 14338497, 14431256, 14523722, 14615898, 14707788, 14799396, 14890723, 14981774, 15072551, 15163058, 15253297, 15343271, 15432983, 15522436, 15611632, 15700574, 15789266, 15877708, 15965905, 16053858, 16141570, 16229043, 16316279, 16403282, 16490052, 16576593, 16662907, 16748995, 16834860, 16920505, 17005930, 17091138, 17176132, 17260913, 17345482, 17429842, 17513996, 17597943, 17681687, 17765230, 17848572, 17931716, 18014663, 18097416, 18179975, 18262342, 18344520, 18426509, 18508311, 18589928, 18671361, 18752611, 18833681, 18914571, 18995284, 19075819, 19156180, 19236367, 19316381, 19396224, 19475898, 19555403, 19634741, 19713913, 19792920, 19871763, 19950445, 20028966, 20107326, 20185528, 20263573, 20341461, 20419194, 20496773, 20574199, 20651473, 20728596, 20805569, 20882394, 20959070, 21035600, 21111985, 21188225, 21264321, 21340274, 21416086, 21491757, 21567288, 21642680, 21717934, 21793050, 21868031, 21942876, 22017587, 22092165, 22166609, 22240922, 22315104, 22389155, 22463078, 22536871, 22610537, 22684076, 22757489, 22830776, 22903939, 22976977, 23049893, 23122686, 23195358, 23267909, 23340339, 23412650, 23484843, 23556917, 23628874, 23700714, 23772438, 23844047, 23915541, 23986921, 24058188, 24129342, 24200384, 24271315, 24342135, 24412844, 24483444, 24553935, 24624318, 24694593, 24764760, 24834822, 24904777, 24974626, 25044371, 25114012, 25183548, 25252982, 25322313, 25391541, 25460669, 25529695, 25598620, 25667446, 25736172];
    constructor() {}

    function testTimeCurve() public {

        for (uint256 i = 1; i < 256; i++) {
            assertEq(outputs[i-1], TimeCurve.calc(i));
        }
    }

}
