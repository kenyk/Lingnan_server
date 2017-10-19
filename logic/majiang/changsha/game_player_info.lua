local game_player_info = {}

--agent to server

game_player_info.card_info = {
	handCards = {},
	outCards = {},
	pengCards = {},
	gangCards = {}, --[card] = 1:暗杠 [card] = 2:明杠 []
	stackCards = {},
	chiCards = {},
	huCard = 0
}

game_player_info.balance_info = {
	gangPoint = 0,
	huPoint = 0,
	birdPoint = 0,
	birdCard = {},
	huType = 0, 		 --1:自摸、2:接炮、3:抢杠胡,4:放炮、5:被抢杠  0:没胡
	gangType = {}    --{anGang:1,jieGang:1,fangGang:1,mingGang:1}
}

game_player_info.base_info = {
	chair_id = 0,
	uid = 0,
	url = "",
	nickname = "",
	point = 1000,
}

game_player_info.balance_result = {
	ziMo = 0,
    jiePao = 0,
    dianPao = 0,
    anGang = 0,
    mingGang = 0,
    suoGang = 0,
    point = 0
}

game_player_info.changsha_balance_info = {
    getpoint = 0,
    getbird = 0,
    first_hu = "",
    first_hu_tmp = {},
    hu_info = "",
    hu_info_tmp = {},
    huType = 0,
    chair_id = 0
}

game_player_info.changsha_balance_result= {
    xiaohuzimo = 0,
    dahuzimo = 0,
    xiaohudianpao = 0,
    dahudianpao = 0,
    xiaohujiepao = 0,
    dahujiepao = 0,
    point = 0
}


return game_player_info
