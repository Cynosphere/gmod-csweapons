AddCSLuaFile()

SWEP.Spawnable = false
SWEP.UseHands = true
SWEP.DrawAmmo = true
SWEP.Category = "Counter Strike: Source"

if CLIENT then
	SWEP.CrosshairDistance = 0
	local cl_crosshaircolor = CreateConVar( "cl_crosshaircolor", "0", FCVAR_ARCHIVE )
	local cl_dynamiccrosshair = CreateConVar( "cl_dynamiccrosshair", "1", FCVAR_ARCHIVE )
	local cl_scalecrosshair = CreateConVar( "cl_scalecrosshair", "1", FCVAR_ARCHIVE )
	local cl_crosshairscale = CreateConVar( "cl_crosshairscale", "0", FCVAR_ARCHIVE )
	local cl_crosshairalpha = CreateConVar( "cl_crosshairalpha", "200", FCVAR_ARCHIVE )
	local cl_crosshairusealpha = CreateConVar( "cl_crosshairusealpha", "0", FCVAR_ARCHIVE )
end

function SWEP:Initialize()
	self:SetHoldType( "normal" )
	self:SetDelayFire( true )
	
	self:SetWeaponType( self.WeaponTypeToString[self:GetWeaponInfo().WeaponType] )
end

SWEP.WeaponTypeToString = {
	Knife = CS_WEAPONTYPE_KNIFE,
	Pistol = CS_WEAPONTYPE_PISTOL,
	Rifle = CS_WEAPONTYPE_RIFLE,
	Shotgun = CS_WEAPONTYPE_SHOTGUN,
	SniperRifle = CS_WEAPONTYPE_SNIPER_RIFLE,
	SubMachineGun = CS_WEAPONTYPE_SUBMACHINEGUN,
	Machinegun = CS_WEAPONTYPE_MACHINEGUN,
	C4 = CS_WEAPONTYPE_C4,
	Grenade = CS_WEAPONTYPE_GRENADE,
}

--[[
	returns the raw data parsed from the vdf in table form,
	some of this data is already applied to the weapon table ( such as .Slot, .PrintName and etc )
]]
function SWEP:GetWeaponInfo()
	return self._WeaponInfo
end

function SWEP:SetupDataTables()
	self:NetworkVar( "Float" , 0 , "NextPrimaryAttack" )
	self:NetworkVar( "Float" , 1 , "NextSecondaryAttack" )
	self:NetworkVar( "Float" , 2 , "Accuracy" )
	self:NetworkVar( "Float" , 3 , "NextIdle" )
	self:NetworkVar( "Float" , 4 , "NextDecreaseShotsFired" )
	
	self:NetworkVar( "Int"	, 0 , "WeaponType" )
	self:NetworkVar( "Int"	, 1 , "ShotsFired" )
	self:NetworkVar( "Int"	, 2 , "Direction" )
	
	self:NetworkVar( "Bool"	, 0 , "InReload" )
	self:NetworkVar( "Bool" , 1 , "HasSilencer" )
	self:NetworkVar( "Bool"	, 2 , "DelayFire" )
	
end

function SWEP:Deploy()
	self:SetNextDecreaseShotsFired( CurTime() )
	self:SetShotsFired( 0 )
	self:SetAccuracy( 0.2 )
	
	self:SendWeaponAnim( self:GetDeployActivity() )
	self:SetNextPrimaryAttack( CurTime() + self:SequenceDuration() )
	self:SetNextSecondaryAttack( CurTime() + self:SequenceDuration() )
	
	if IsValid( self:GetOwner() ) and self:GetOwner():IsPlayer() then
		self:GetOwner():SetFOV( 0 , 0 )
	end
	
	return true
end

function SWEP:Reload()
	if self:GetMaxClip1() ~= -1 and not self:InReload() and self:GetNextPrimaryAttack() < CurTime() then
		self:SetShotsFired( 0 )
		
		local reload = self:MainReload( ACT_VM_RELOAD )
		
	end
end

--Jvs: can't call it DefaultReload because there's already one in the weapon's metatable and I'd rather not cause conflicts

function SWEP:MainReload( act )
	local pOwner = self:GetOwner()
	
	-- If I don't have any spare ammo, I can't reload
	if pOwner:GetAmmoCount( self:GetPrimaryAmmoType() ) <= 0 then
		return false
	end
	
	local bReload = false
	
	-- If you don't have clips, then don't try to reload them.
	if self:GetMaxClip1() ~= -1 then
		-- need to reload primary clip?
		local primary	= math.min( self:GetMaxClip1() - self:Clip1(), pOwner:GetAmmoCount(self:GetPrimaryAmmoType()))
		if primary ~= 0 then
			bReload = true
		end
	end
	
	if self:GetMaxClip2() ~= -1 then
		-- need to reload secondary clip?
		local secondary = math.min( self:GetMaxClip2() - self:Clip2(), pOwner:GetAmmoCount( self:GetSecondaryAmmoType() ))
		if secondary ~= 0 then
			bReload = true
		end
	end

	if not bReload then
		return false
	end
	
	self:WeaponSound( "reload" )

	self:SendWeaponAnim( act )

	-- Play the player's reload animation
	if pOwner:IsPlayer() then
		pOwner:DoReloadEvent()
	end

	local flSequenceEndTime = CurTime() + self:SequenceDuration()
	
	self:SetNextPrimaryAttack( flSequenceEndTime )
	self:SetNextSecondaryAttack( flSequenceEndTime )
	self:SetInReload( true )
	
	return true
end

function SWEP:GetMaxClip1()
	return self.Primary.ClipSize
end

function SWEP:GetMaxClip2()
	return self.Secondary.ClipSize
end

function SWEP:PrimaryAttack()

end

function SWEP:SecondaryAttack()

end

function SWEP:Think()
	local pPlayer = self:GetOwner()

	if not IsValid( pPlayer ) then
		return
	end
	
	--[[
		Jvs:
			this is where the reload actually ends, this might be moved into its own function so other coders
			can add other behaviours ( such as cs:go finishing the reload with a different delay, based on when the 
			magazine actually gets inserted )
	]]
	if self:InReload() and self:GetNextPrimaryAttack() <= CurTime() then
		-- complete the reload. 
		local j = math.min( self:GetMaxClip1() - self:Clip1(), pPlayer:GetAmmoCount( self:GetPrimaryAmmoType() ) )
		
		-- Add them to the clip
		self:SetClip1( self:Clip1() + j )
		pPlayer:RemoveAmmo( j, self:GetPrimaryAmmoType() )

		self:SetInReload( false )
	end
	
	local plycmd = pPlayer:GetCurrentCommand()
	
	if not plycmd:KeyDown( IN_ATTACK ) and not plycmd:KeyDown( IN_ATTACK2 ) then
		-- no fire buttons down

		-- The following code prevents the player from tapping the firebutton repeatedly 
		-- to simulate full auto and retaining the single shot accuracy of single fire
		if self:GetDelayFire() then
			self:SetDelayFire( false )

			if self:GetShotsFired() > 15 then
				self:SetShotsFired( 15 )
			end
			
			self:SetNextDecreaseShotsFired( CurTime() + 0.4 )
		end

		-- if it's a pistol then set the shots fired to 0 after the player releases a button
		if self:IsPistol() then
			self:SetShotsFired( 0 )
		else
			if self:GetShotsFired() > 0 and self:GetNextDecreaseShotsFired() < CurTime() then
				self:SetNextDecreaseShotsFired( CurTime() + 0.0225 )
				self:SetShotsFired( self:GetShotsFired() - 1 )
			end
		end

		self:Idle()
	end
end

function SWEP:Idle()
	if CurTime() > self:GetNextIdle() then
		self:SendWeaponAnim( ACT_VM_IDLE )
	end
end

function SWEP:Holster()
	
	return true
end

function SWEP:InReload()
	return self:GetInReload()
end

function SWEP:IsPistol()
	return self:GetWeaponType() == CS_WEAPONTYPE_PISTOL
end

function SWEP:IsAwp()
	return false
end

function SWEP:IsSilenced()
	return self:GetHasSilencer()
end

function SWEP:GetDeployActivity()
	if self:IsSilenced() then
		return ACT_VM_DRAW_SILENCED
	else
		return ACT_VM_DRAW
	end
end

--TODO: use getweaponinfo and shit to emit the sound here
function SWEP:WeaponSound( soundtype )
	if not self:GetWeaponInfo() then return end
	
	local sndname = self:GetWeaponInfo().SoundData[soundtype]
	
	if sndname then
		self:EmitSound( sndname , nil , nil , nil , CHAN_AUTO )
	end
end

function SWEP:PlayEmptySound()
	if self:IsPistol() then
		self:EmitSound( "Default.ClipEmpty_Pistol" , nil , nil , nil , CHAN_AUTO )	--an actual undocumented feature!
	else
		self:EmitSound( "Default.ClipEmpty_Rifle" , nil , nil , nil , CHAN_AUTO )
	end
end

function SWEP:KickBack( up_base, lateral_base, up_modifier, lateral_modifier, up_max, lateral_max, direction_change )
	if not self:GetOwner():IsPlayer() then 
		return 
	end
	
	local flKickUp
	local flKickLateral
	
	--[[
		Jvs:
			I implemented the shots fired and direction stuff on the cs base because it would've been dumb to do it
			on the player, since it's reset on a gun basis anyway
	]]
	if self:GetShotsFired() == 1 then-- This is the first round fired
		flKickUp = up_base
		flKickLateral = lateral_base
	else
		flKickUp = up_base + self:GetShotsFired() * up_modifier
		flKickLateral = lateral_base + self:GetShotsFired() * lateral_modifier
	end


	local angle = self:GetOwner():GetViewPunchAngles()

	angle.x = angle.x - flKickUp
	if angle.x < -1 * up_max then
		angle.x = -1 * up_max
	end
	
	if self:GetDirection() == 1 then
		angle.y = angle.y + flKickLateral
		if angle.y > lateral_max then
			angle.y = lateral_max
		end
	else
		angle.y = angle.y - flKickLateral
		if angle.y < -1 * lateral_max then
			angle.y = -1 * lateral_max
		end
	end
	
	--[[
		Jvs: uhh I don't get this code, so they run a random int from 0 up to direction_change, 
		( which varies from 5 to 9 in the ak47 case)
		if the random craps out a 0, they make the direction negative and damp it by 1
		the actual direction in the whole source code is only used above, and it produces a different kick if it's at 1
		
		I don't know if the guy that made this was a genius or..
	]]
	
	if math.floor( util.SharedRandom( "KickBack" , 0 , direction_change ) ) == 0 then
		self:SetDirection( 1 - self:GetDirection() )
	end
	
	self:GetOwner():SetViewPunchAngles( angle )
end

if CLIENT then
	local cl_crosshaircolor = GetConVar( "cl_crosshaircolor" )
	local cl_dynamiccrosshair = GetConVar( "cl_dynamiccrosshair" )
	local cl_scalecrosshair = GetConVar( "cl_scalecrosshair" )
	local cl_crosshairscale = GetConVar( "cl_crosshairscale" )
	local cl_crosshairalpha = GetConVar( "cl_crosshairalpha" )
	local cl_crosshairusealpha = GetConVar( "cl_crosshairusealpha" )
	
	function SWEP:DoDrawCrosshair( x , y )
		
		local iDistance = self:GetWeaponInfo().CrosshairMinDistance -- The minimum distance the crosshair can achieve...
		
		local iDeltaDistance = self:GetWeaponInfo().CrosshairDeltaDistance -- Distance at which the crosshair shrinks at each step
		
		if cl_dynamiccrosshair:GetBool() then
			if not self:GetOwner():OnGround() then
				 iDistance = iDistance * 2.0
			elseif self:GetOwner():Crouching() then
				 iDistance = iDistance * 0.5
			elseif self:GetOwner():GetAbsVelocity():Length() > 100 then
				 iDistance = iDistance * 1.5
			end
		end
	
		
		
		if self.CrosshairDistance <= iDistance then
			self.CrosshairDistance = self.CrosshairDistance - 0.1 + self.CrosshairDistance * 0.013
		else
			self.CrosshairDistance = math.min( 15, self.CrosshairDistance + iDeltaDistance )
		end
		
		
		if self.CrosshairDistance < iDistance then
			 self.CrosshairDistance = iDistance
		end

		--scale bar size to the resolution
		local crosshairScale = cl_crosshairscale:GetInt()
		if crosshairScale < 1 then
			if ScrH() <= 600 then
				crosshairScale = 600
			elseif ScrH() <= 768 then
				crosshairScale = 768
			else
				crosshairScale = 1200
			end
		end
		
		local scale
		
		if not cl_scalecrosshair:GetBool() then
			scale = 1
		else
			scale = ScrH() / crosshairScale
		end

		local iCrosshairDistance = math.ceil( self.CrosshairDistance * scale )
		
		local iBarSize = ScreenScale( 5 ) + (iCrosshairDistance - iDistance) / 2

		iBarSize = math.max( 1, iBarSize * scale )
		
		local iBarThickness = math.max( 1, math.floor( scale + 0.5 ) )

		local r, g, b
		
		if cl_crosshaircolor:GetInt() == 0 then
			r = 50
			g = 250
			b = 50
		elseif cl_crosshaircolor:GetInt() == 1 then
			r = 250
			g = 50
			b = 50
		elseif cl_crosshaircolor:GetInt() == 2 then
			r = 50
			g = 50
			b = 250
		elseif cl_crosshaircolor:GetInt() == 3 then
			r = 250
			g = 250
			b = 50
		elseif cl_crosshaircolor:GetInt() == 4 then
			r = 50
			g = 250
			b = 250
		else
			r = 50
			g = 250
			b = 50
		end
		
		local alpha = math.Clamp( cl_crosshairalpha:GetInt(), 0, 255 )
		surface.SetDrawColor( r, g, b, alpha )
		
		draw.NoTexture()
		--surface.DrawRect( 0 , 0 , 1000 , 1000 )
		
		--[[
		
		if ( not m_iCrosshairTextureID )
		{
			CHudTexture *pTexture = gHUD.GetIcon( "whiteAdditive" )
			if ( pTexture )
			{
				m_iCrosshairTextureID = pTexture->textureId
			}
		}
		]]

		if not cl_crosshairusealpha:GetBool() then
			surface.SetDrawColor( r, g, b, 200 )
			--surface.SetTexture( m_iCrosshairTextureID )
		end

		local iHalfScreenWidth = 0
		local iHalfScreenHeight = 0

		local iLeft		= iHalfScreenWidth - ( iCrosshairDistance + iBarSize )
		local iRight	= iHalfScreenWidth + iCrosshairDistance + iBarThickness
		local iFarLeft	= iBarSize
		local iFarRight	= iBarSize

		if not cl_crosshairusealpha:GetBool() then
			-- Additive crosshair
			surface.DrawTexturedRect( x + iLeft, y + iHalfScreenHeight, iFarLeft, iHalfScreenHeight + iBarThickness )
			surface.DrawTexturedRect( x + iRight, y + iHalfScreenHeight, iFarRight, iHalfScreenHeight + iBarThickness )
		else
			-- Alpha-blended crosshair
			surface.DrawRect( x + iLeft, y + iHalfScreenHeight, iFarLeft, iHalfScreenHeight + iBarThickness )
			surface.DrawRect( x + iRight, y + iHalfScreenHeight, iFarRight, iHalfScreenHeight + iBarThickness )
		end
		
		local iTop		= iHalfScreenHeight - ( iCrosshairDistance + iBarSize )
		local iBottom		= iHalfScreenHeight + iCrosshairDistance + iBarThickness
		local iFarTop		= iBarSize
		local iFarBottom	= iBarSize

		if not cl_crosshairusealpha:GetBool() then
			-- Additive crosshair
			surface.DrawTexturedRect( x + iHalfScreenWidth, y + iTop, iHalfScreenWidth + iBarThickness, iFarTop )
			surface.DrawTexturedRect( x + iHalfScreenWidth, y + iBottom, iHalfScreenWidth + iBarThickness, iFarBottom )
		else
			-- Alpha-blended crosshair
			surface.DrawRect( x + iHalfScreenWidth, y + iTop, iHalfScreenWidth + iBarThickness, iFarTop )
			surface.DrawRect( x + iHalfScreenWidth, y + iBottom, iHalfScreenWidth + iBarThickness, iFarBottom )
		end
		
		return true
	end

end