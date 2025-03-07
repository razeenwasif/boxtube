import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { 
  Container, 
  Box, 
  Typography, 
  TextField, 
  Button, 
  Paper,
  Alert,
  Link
} from '@mui/material';
import { useAuth } from '../../contexts/AuthContext';

const Login = () => {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  
  const { login } = useAuth();
  const navigate = useNavigate();
  
  const handleSubmit = async (e) => {
    e.preventDefault();
    
    try {
      setError('');
      setLoading(true);
      await login(username, password);
      navigate('/');
    } catch (error) {
      setError(error.message);
    } finally {
      setLoading(false);
    }
  };
  
  return (
    <Container maxWidth="sm" sx={{ py: 4 }}>
      <Paper 
        elevation={3} 
        sx={{ 
          p: 4, 
          backgroundColor: 'var(--card-bg)',
          border: '1px solid var(--border-color)',
          borderRadius: '12px'
        }}
      >
        <Typography 
          variant="h4" 
          component="h1" 
          gutterBottom 
          sx={{ 
            color: 'var(--text-primary)',
            textAlign: 'center',
            fontWeight: 500
          }}
        >
          Sign In
        </Typography>
        
        {error && (
          <Alert severity="error" sx={{ mb: 2 }}>
            {error}
          </Alert>
        )}
        
        <Box component="form" onSubmit={handleSubmit} noValidate>
          <TextField
            margin="normal"
            required
            fullWidth
            id="username"
            label="Username"
            name="username"
            autoComplete="username"
            autoFocus
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            sx={{
              mb: 2,
              '& .MuiOutlinedInput-root': {
                '& fieldset': {
                  borderColor: 'var(--border-color)',
                },
                '&:hover fieldset': {
                  borderColor: 'var(--text-secondary)',
                },
                '&.Mui-focused fieldset': {
                  borderColor: 'var(--primary-color)',
                },
              },
              '& .MuiInputLabel-root': {
                color: 'var(--text-secondary)',
              },
              '& .MuiInputBase-input': {
                color: 'var(--text-primary)',
              },
            }}
          />
          
          <TextField
            margin="normal"
            required
            fullWidth
            name="password"
            label="Password"
            type="password"
            id="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            sx={{
              mb: 3,
              '& .MuiOutlinedInput-root': {
                '& fieldset': {
                  borderColor: 'var(--border-color)',
                },
                '&:hover fieldset': {
                  borderColor: 'var(--text-secondary)',
                },
                '&.Mui-focused fieldset': {
                  borderColor: 'var(--primary-color)',
                },
              },
              '& .MuiInputLabel-root': {
                color: 'var(--text-secondary)',
              },
              '& .MuiInputBase-input': {
                color: 'var(--text-primary)',
              },
            }}
          />
          
          <Button
            type="submit"
            fullWidth
            variant="contained"
            disabled={loading}
            sx={{
              mb: 2,
              backgroundColor: 'var(--primary-color)',
              '&:hover': {
                backgroundColor: 'var(--primary-color-dark)',
              },
              '&.Mui-disabled': {
                backgroundColor: 'rgba(255, 0, 0, 0.3)',
              }
            }}
          >
            Sign In
          </Button>
          
          <Box sx={{ textAlign: 'center' }}>
            <Typography variant="body2" color="var(--text-secondary)">
              Don't have an account?{' '}
              <Link 
                href="/signup" 
                sx={{ 
                  color: 'var(--primary-color)',
                  textDecoration: 'none',
                  '&:hover': {
                    textDecoration: 'underline'
                  }
                }}
              >
                Sign Up
              </Link>
            </Typography>
          </Box>
        </Box>
      </Paper>
    </Container>
  );
};

export default Login; 