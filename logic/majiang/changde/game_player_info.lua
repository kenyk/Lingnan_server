local game_player_info = {}

--agent to server

game_player_info.card_info = {
	handCards = {},
	outCards = {},
	pengCards = {},
	gangCards = {}, --[card] = 1:暗杠 [card] = 2:明杠
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

return game_player_info
