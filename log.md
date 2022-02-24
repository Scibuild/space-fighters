# 2021-06-14

ok so game is going well but i thought it would be fun to write down what ive been doing and where im going

at the moment im rewriting the asteroid geometry and stuff to be stored in the asteroid struct itself rather than just being allocated and like left there afterwards oops. this was because i wanted to write something to restart the game except u can just deinit the arena allocator apparently, it wont let u use it any more. then i realised that i dont need to deinit if im using fixed memory in the struct yay :D

i kinda want to do a menu thing but doing fonts sounds hard. i should probably learn how to deal with surfaces so that like I can use those for the fonts

the plan is to eventually do networking.

also sparse arrays what are those
