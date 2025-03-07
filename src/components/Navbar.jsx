import { Stack, AppBar, Box, IconButton, Tooltip } from '@mui/material'; // Stack arranges items one dimensionally as a column or row
import { Link } from 'react-router-dom';
import { History } from '@mui/icons-material';
import { logo } from '../utils/constants';
import SearchBar from './SearchBar';

const Navbar = () => (
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
      </Stack>
    </Stack>
  </AppBar>
);

export default Navbar