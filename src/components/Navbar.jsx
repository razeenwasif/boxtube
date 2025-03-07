import { useState } from 'react';
import { Stack, AppBar, Box, IconButton, Tooltip, Avatar, Menu, MenuItem, Typography, Button } from '@mui/material';
import { Link, useNavigate } from 'react-router-dom';
import { History, Search as SearchIcon, VideoLibrary, Logout, Settings, Person } from '@mui/icons-material';
import { logo } from '../utils/constants';
import SearchBar from './SearchBar';
import { useAuth } from '../contexts/AuthContext';

const Navbar = () => {
  const [anchorEl, setAnchorEl] = useState(null);
  const { currentUser } = useAuth();
  const navigate = useNavigate();
  
  const handleProfileMenuOpen = (event) => {
    setAnchorEl(event.currentTarget);
  };

  const handleMenuClose = () => {
    setAnchorEl(null);
  };
  
  const handleProfileClick = () => {
    navigate('/profile');
    handleMenuClose();
  };
  
  const handleLoginClick = () => {
    navigate('/login');
    handleMenuClose();
  };
  
  const handleSignupClick = () => {
    navigate('/signup');
    handleMenuClose();
  };
  
  return (
    <AppBar 
      position="sticky"
      sx={{ 
        background: 'var(--navbar-bg)',
        backdropFilter: 'blur(10px)',
        borderBottom: '1px solid var(--border-color)',
        boxShadow: '0 4px 12px rgba(0, 0, 0, 0.3)',
      }}
    >
      <Stack 
        direction="row" 
        alignItems="center" 
        p={2} 
        sx={{ 
          justifyContent: 'space-between',
        }}
      > 
        <Link to="/" style={{ display: 'flex', alignItems: 'center' }}>
          <Box
            component="img"
            src={logo}
            alt="logo"
            sx={{
              height: 40,
              filter: 'brightness(1.2)',
              transition: 'transform 0.2s ease, filter 0.2s ease',
              '&:hover': {
                transform: 'scale(1.05)',
                filter: 'brightness(1.4) drop-shadow(0 0 4px rgba(255, 77, 77, 0.5))',
              }
            }}
          />
        </Link>
        <Stack direction="row" alignItems="center" spacing={2}>
          <SearchBar />
          
          <Tooltip title="Search History">
            <Link to="/search-history">
              <IconButton
                sx={{
                  color: 'var(--text-secondary)',
                  '&:hover': {
                    color: 'var(--primary-color)',
                    backgroundColor: 'rgba(255, 0, 0, 0.08)'
                  }
                }}
              >
                <SearchIcon />
              </IconButton>
            </Link>
          </Tooltip>
          
          <Tooltip title="Watch History">
            <Link to="/history">
              <IconButton
                sx={{
                  color: 'var(--text-secondary)',
                  '&:hover': {
                    color: 'var(--primary-color)',
                    backgroundColor: 'rgba(255, 0, 0, 0.08)'
                  }
                }}
              >
                <History />
              </IconButton>
            </Link>
          </Tooltip>
          
          <Tooltip title="Playlists">
            <Link to="/playlists">
              <IconButton
                sx={{
                  color: 'var(--text-secondary)',
                  '&:hover': {
                    color: 'var(--primary-color)',
                    backgroundColor: 'rgba(255, 0, 0, 0.08)'
                  }
                }}
              >
                <VideoLibrary />
              </IconButton>
            </Link>
          </Tooltip>
          
          {currentUser ? (
            <>
              <Tooltip title="Account">
                <IconButton
                  onClick={handleProfileMenuOpen}
                  sx={{
                    p: 0,
                    border: '2px solid transparent',
                    '&:hover': {
                      border: '2px solid var(--primary-color)',
                    }
                  }}
                >
                  <Avatar 
                    alt={currentUser.username}
                    src={currentUser.profilePicture}
                    sx={{ width: 32, height: 32 }}
                  />
                </IconButton>
              </Tooltip>
              
              <Menu
                anchorEl={anchorEl}
                id="account-menu"
                open={Boolean(anchorEl)}
                onClose={handleMenuClose}
                PaperProps={{
                  sx: {
                    backgroundColor: 'var(--card-bg)',
                    border: '1px solid var(--border-color)',
                    boxShadow: 'var(--card-hover-shadow)',
                    mt: 1.5,
                    '& .MuiMenuItem-root': {
                      color: 'var(--text-primary)',
                      '&:hover': {
                        backgroundColor: 'rgba(255, 0, 0, 0.08)'
                      }
                    }
                  }
                }}
                transformOrigin={{ horizontal: 'right', vertical: 'top' }}
                anchorOrigin={{ horizontal: 'right', vertical: 'bottom' }}
              >
                <Box sx={{ px: 2, py: 1 }}>
                  <Typography variant="subtitle1" color="var(--text-primary)">
                    {currentUser.username}
                  </Typography>
                  <Typography variant="body2" color="var(--text-secondary)">
                    {currentUser.email}
                  </Typography>
                </Box>
                
                <MenuItem onClick={handleProfileClick}>
                  Profile
                </MenuItem>
              </Menu>
            </>
          ) : (
            <>
              <Button
                variant="outlined"
                onClick={handleLoginClick}
                sx={{
                  color: 'var(--text-primary)',
                  borderColor: 'var(--border-color)',
                  '&:hover': {
                    borderColor: 'var(--primary-color)',
                    backgroundColor: 'rgba(255, 0, 0, 0.08)'
                  }
                }}
              >
                Sign In
              </Button>
              
              <Button
                variant="contained"
                onClick={handleSignupClick}
                sx={{
                  backgroundColor: 'var(--primary-color)',
                  '&:hover': {
                    backgroundColor: 'var(--primary-color-dark)'
                  }
                }}
              >
                Sign Up
              </Button>
            </>
          )}
        </Stack>
      </Stack>
    </AppBar>
  );
};

export default Navbar;